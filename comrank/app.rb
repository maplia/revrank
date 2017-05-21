$LOAD_PATH << '../comrank/lib'

require 'active_support/all'
require 'sinatra/base'
require 'sinatra/config_file'
require 'sinatra/multi_route'
require 'sinatra/json'
require 'sinatra/jsonp'
require 'sinatra/cross_origin'
require 'sinatra/default_charset'
require 'sinatra_more/markup_plugin'
require 'tilt/haml'
require 'rack/mobile-detect'
require 'rack/protection'
require 'cxbrank/site_settings'
require 'cxbrank/helpers'
require 'cxbrank/const'
require 'cxbrank/authenticate'
require 'cxbrank/master'
require 'cxbrank/master/music_set'
require 'cxbrank/user'
require 'cxbrank/skill'
require 'cxbrank/master/app'
require 'cxbrank/playdata/app'

module CxbRank
  class AppBase < Sinatra::Base
    register Sinatra::ConfigFile
    register Sinatra::CrossOrigin
    register Sinatra::DefaultCharset
    register Sinatra::MultiRoute
    register SinatraMore::MarkupPlugin
    register CxbRank::Helpers
    register CxbRank::Master
    register CxbRank::PlayData

    config_file File.expand_path(CONFIG_FILE, Dir.pwd)

    configure do
      set :environment, settings.environment.to_sym
      set :sessions,
        :key => settings.session_key, :secret => settings.secret,
        :expire_after => EXPIRE_MINUTES * 60
      set :public_dir, File.expand_path('public', Dir.pwd)
      set :method_override, true
      enable :cross_origin
      set :default_charset, 'utf-8'
      use Rack::MobileDetect
      mime_type :css, 'text/css'
      mime_type :js, 'text/javascript'
    end

    before do
      Time.zone = 'Tokyo'
      SiteSettings.settings = settings
      settings.views = ['views',
        SiteSettings.join_comrank_path('views'), SiteSettings.join_comrank_path('views/application'),
      ]
      ActiveRecord::Base.configurations = YAML.load_file(DATABASE_FILE)
      ActiveRecord::Base.establish_connection(settings.environment)
      ActiveRecord::Base.default_timezone = :local
    end

    helpers Sinatra::Jsonp

    helpers do
      def page_last_modified(templates, data_mtime=nil, user=nil)
        if user.present?
          last_modified Time.now
        else
          mtimes = templates.map do |template|
            template.gsub!('#{comrank_path}', SiteSettings.join_comrank_path(''))
            Dir.glob(template).map do |file| File.mtime(file) end
          end.flatten
          mtimes << data_mtime
          last_modified mtimes.compact.max
        end
      end

      def jsonx(data, callback=nil)
        cross_origin
        if callback
          jsonp data, callback
        else
          json data
        end
      end

      def past_date_page(date_string, &block)
        begin
          if date_string.present?
            date = Date.strptime(date_string, '%Y%m%d')
            SiteSettings.pivot_date = date
          else
            date = nil
          end
        rescue ArgumentError
          date_error = true
        end
        if date_error
          haml :error, :layout => true,
            :locals => {:error_no => ERROR_DATE_IS_INVALID, :back_uri => SiteSettings.join_site_base(SITE_TOP_URI)}
        elsif date.present? and date < DATE_LOW_LIMITS[settings.site_mode]
          haml :error, :layout => true,
            :locals => {:error_no => ERROR_DATE_OUT_OF_RANGE, :back_uri => SiteSettings.join_site_base(SITE_TOP_URI)}
        else
          yield date
        end
      end

      def private_page(&block)
        if session[:user_id].blank? or (user = User.find_by_id(session[:user_id])).nil?
          haml :error, :layout => true,
            :locals => {:error_no => ERROR_SESSION_IS_DEAD, :back_uri => SiteSettings.join_site_base(SITE_TOP_URI)}
        else
          yield user
        end
      end

      def public_user_page(&block)
        if params[:user_id].blank?
          haml :error, :layout => true, :locals => {:error_no => ERROR_USERID_IS_UNINPUTED}
        elsif (user = User.find_by_param_id(params[:user_id])).nil?
          haml :error, :layout => true, :locals => {:error_no => ERROR_USERID_IS_UNREGISTERED}
        elsif !user.display
          haml :error, :layout => true, :locals => {:error_no => ERROR_USERID_IS_HIDDEN}
        else
          yield user
        end
      end
    end

    get '/googlee47e6c106efd57d5.html' do
      content_type :html
      send_file 'googlee47e6c106efd57d5.html'
    end

    get '/common/stylesheets/:file_name' do
      content_type :css
      send_file File.expand_path(params[:file_name], SiteSettings.join_comrank_path('stylesheets'))
    end

    get '/common/javascripts/:file_name' do
      content_type :js
      send_file File.expand_path(params[:file_name], SiteSettings.join_comrank_path('javascripts'))
    end

    get SITE_TOP_URI do
      data_mtime = [Master::Music.last_modified, Master::Event.last_modified].compact.max
      user = User.find_by_id(session[:user_id])
      page_last_modified PAGE_TEMPLATE_FILES[SITE_TOP_URI], data_mtime, user
      haml :index, :layout => true, :locals => {:user => user}
    end

    get USAGE_URI do
      page_last_modified PAGE_TEMPLATE_FILES[USAGE_URI]
      haml :usage, :layout => true
    end

    get USER_ADD_URI do
      settings.views << SiteSettings.join_comrank_path('views/user_edit')
      user = User.new
      if session["#{underscore(CxbRank::User)}_temp"].present?
        user.update_by_params!(session[underscore(CxbRank::User)])
      end
      session[:user_added] = false
      haml :user_add, :layout => true, :locals => {:user => user}
    end

    post USER_ADD_URI do
      settings.views << SiteSettings.join_comrank_path('views/user_edit_conf')
      user = User.create_by_params(params[underscore(CxbRank::User)])
      session["#{underscore(CxbRank::User)}_temp"] = Hash[params[underscore(CxbRank::User)]]
      unless user.valid?
        haml :error, :layout => true,
          :locals => {:errors => user.errors, :back_uri => SiteSettings.join_site_base(request.path_info)}
      else
        haml :user_add_conf, :layout => true, :locals => {:user => user}
      end
    end

    put USER_ADD_URI do
      if params[:y].present?
        settings.views << SiteSettings.join_comrank_path('views/user_edit')
        if session[:user_added]
          user = User.find_by_id(session[:user_id])
          haml :user_add_result, :layout => true, :locals => {:user => user}
        else
          begin
            user = User.create_by_params(session["#{underscore(CxbRank::User)}_temp"])
            user.save!
            session[:user_id] = user.id
            session[:user_added] = true
            session["#{underscore(CxbRank::User)}_temp"] = nil
            haml :user_add_result, :layout => true, :locals => {:user => user}
          rescue
            haml :error, :layout => true,
              :locals => {:error_no => ERROR_DATABASE_SAVE_FAILED, :back_uri => SiteSettings.join_site_base(request.path_info)}
          end
        end
      else
        redirect SiteSettings.join_site_base(USER_ADD_URI)
      end
    end

    get USER_LIST_URI do
      settings.views << SiteSettings.join_comrank_path('views/user_list')
      users = User.find_actives
      data_mtime = User.last_modified
      page_last_modified PAGE_TEMPLATE_FILES[USER_LIST_URI], data_mtime
      haml :user_list, :layout => true, :locals => {:users => users}
    end

    post USER_LOGIN_URI do
      session[:user_id] = nil
      error_no = User.authenticate(params[:user_id], params[:password])
      if error_no != NO_ERROR
        haml :error, :layout => true,
          :locals => {:error_no => error_no, :back_uri => SiteSettings.join_site_base(SITE_TOP_URI)}
      else
        session[:user_id] = User.find_by_param_id(params[:user_id]).id
        redirect SiteSettings.join_site_base(SKILL_LIST_EDIT_URI)
      end
    end

    get USER_LOGOUT_URI do
      session[:user_id] = nil
      redirect SiteSettings.join_site_base("#{SITE_TOP_URI}?#{Time.now.to_i}")
    end

    get USER_EDIT_URI do
      private_page do |user|
        settings.views << SiteSettings.join_comrank_path('views/user_edit')
        user.update_by_params!(session[underscore(CxbRank::User)])
        haml :user_edit, :layout => true, :locals => {:user => user}
      end
    end

    post USER_EDIT_URI do
      private_page do |user|
        settings.views << SiteSettings.join_comrank_path('views/user_edit_conf')
        user.update_by_params!(params[underscore(CxbRank::User)])
        session[underscore(CxbRank::User)] = Hash[params[underscore(CxbRank::User)]]
        unless user.valid?
          haml :error, :layout => true,
            :locals => {:errors => user.errors, :back_uri => SiteSettings.join_site_base(request.path_info)}
        else
          haml :user_edit_conf, :layout => true, :locals => {:user => user}
        end
      end
    end

    put USER_EDIT_URI do
      if params[:y].present?
        private_page do |user|
          settings.views << SiteSettings.join_comrank_path('views/user_edit')
          begin
            user.update_by_params!(session[underscore(CxbRank::User)])
            user.save!
            session[underscore(CxbRank::User)] = nil
            redirect SiteSettings.join_site_base(SKILL_LIST_EDIT_URI)
          rescue
            haml :error, :layout => true,
              :locals => {:error_no => ERROR_DATABASE_SAVE_FAILED, :back_uri => SiteSettings.join_site_base(request.path_info)}
          end
        end
      else
        redirect SiteSettings.join_site_base(USER_EDIT_URI)
      end
    end

    get SCORE_RANK_URI do
      settings.views << SiteSettings.join_comrank_path('views/rank_score')
      music_set = Master::MusicSet.new
      music_set.load!
      data_mtime = music_set.last_modified
      page_last_modified PAGE_TEMPLATE_FILES[SCORE_RANK_URI], data_mtime
      haml :rank_score, :layout => true, :locals => {:music_set => music_set}
    end

    get "#{SCORE_RANK_DETAIL_URI}/:music_text_id?/?:diff?" do
      if params[:music_text_id].blank?
        haml :error, :layout => true, :locals => {:error_no => ERROR_MUSIC_IS_UNDECIDED}
      elsif (music = Music.find_by(:text_id => params[:music_text_id])).nil?
        haml :error, :layout => true, :locals => {:error_no => ERROR_MUSIC_NOT_EXIST}
      elsif params[:diff].blank?
        haml :error, :layout => true, :locals => {:error_no => ERROR_DIFF_IS_UNDECIDED}
      elsif (diff = SiteSettings.music_diffs.invert[params[:diff].upcase]).nil? or !music.exist?(diff)
        haml :error, :layout => true, :locals => {:error_no => ERROR_DIFF_NOT_EXIST}
      else
        settings.views << SiteSettings.join_comrank_path('views/rank_score_detail')
        fixed_title = "#{PAGE_TITLES[SCORE_RANK_DETAIL_URI]} [#{music.full_title} (#{SiteSettings.music_diffs[diff]})]"
        skills = Skill.get_rank_data(music, diff)
        haml :rank_score_detail, :layout => true, :locals => {
          :music => music, :diff => diff, :skills => skills, :fixed_title => fixed_title}
      end
    end
  end
end
