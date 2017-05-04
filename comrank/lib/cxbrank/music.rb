require 'cxbrank/master_base'
require 'cxbrank/const'
require 'cxbrank/site_settings'
require 'cxbrank/monthly'
require 'cxbrank/course'

module CxbRank
  class Music < MasterBase
    include Comparable
    has_one :monthly, -> {where 'span_s <= ? and span_e >= ?',
      (SiteSettings.pivot_time || Time.now), (SiteSettings.pivot_time || Time.now)}
    has_many :legacy_charts

    def self.create_by_request(body)
      music = self.where(:lookup_key => body[:lookup_key]).first
      unless music
        music = self.new
        music.number = 0
        music.text_id = body[:text_id]
        music.title = body[:title]
        music.sort_key = body[:sort_key]
        music.lookup_key = body[:lookup_key]
        music.limited = false
        music.hidden = true
        music.unlock_unl = UNLOCK_UNL_TYPE_SP
        music.appear = REV_VERSION_SUNRISE
        music.category = REV_CATEGORY_ORIGINAL
        music.added_at = Date.today
      end
      music.jacket = body[:jacket]
      MUSIC_DIFF_PREFIXES.values.each do |prefix|
        next unless body[prefix.to_sym]
        music.send("#{prefix}_level=", body[prefix.to_sym][:level])
        music.send("#{prefix}_notes=", body[prefix.to_sym][:notes])
      end
      if music.unl_level_changed?
        music.unlock_unl = UNLOCK_UNL_TYPE_SP
        music.added_at_unl = Date.today
      end
      return music
    end

    def self.find_by_param_id(text_id)
      return self.where(:text_id => text_id).first
    end

    def self.find_actives
      if SiteSettings.sunrise_or_later_mode?
        return super.order(:appear, :sort_key)
      else
        return super.order(:number, :sort_key)
      end
    end

    def full_title
      return subtitle ? "#{title} #{subtitle}" : title
    end

    def level(diff)
      if SiteSettings.pivot_date.present? and legacy_charts.present?
        legacy_charts.each do |legacy_chart|
          if (legacy_chart.span_s..(legacy_chart.span_e-1)).include?(SiteSettings.pivot_date)
            return legacy_chart.level(diff)
          end
        end
      end
      return send("#{MUSIC_DIFF_PREFIXES[diff]}_level")
    end

    def legacy_level(diff)
      if legacy_charts.blank?
        return nil
      else
        return legacy_charts[0].level(diff)
      end
    end

    def notes(diff)
      if SiteSettings.pivot_date.present? and legacy_charts.present?
        legacy_charts.each do |legacy_chart|
          if (legacy_chart.span_s..(legacy_chart.span_e-1)).include?(SiteSettings.pivot_date)
            return legacy_chart.notes(diff)
          end
        end
      end
      return send("#{MUSIC_DIFF_PREFIXES[diff]}_notes")
    end

    def legacy_notes(diff)
      if legacy_charts.blank?
        return nil
      else
        return legacy_charts[0].notes(diff)
      end
    end

    def max_notes
      note_data = []
      SiteSettings.music_diffs.keys.each do |diff|
        note_data << (notes(diff) || 0)
      end
      return note_data.max
    end

    def exist?(diff)
      return level(diff).present?
    end

    def exist_legacy?(diff)
      return legacy_level(diff).present?
    end

    def monthly?
      return monthly.present?
    end

    def deleted?
      return deleted && deleted_at <= (SiteSettings.pivot_date || Date.today)
    end

    def level_to_s(diff)
      unless exist?(diff)
        return '-'
      else
        return (level(diff) == 0) ? '-' : sprintf(SiteSettings.level_format, level(diff))
      end
    end

    def legacy_level_to_s(diff)
      unless exist_legacy?(diff)
        return '-'
      else
        return (legacy_level(diff) == 0) ? '-' : sprintf(SiteSettings.level_format, legacy_level(diff))
      end
    end

    def notes_to_s(diff)
      unless exist?(diff)
        return '-'
      else
        return (notes(diff) == 0) ? '???' : sprintf('%d', notes(diff))
      end
    end

    def legacy_notes_to_s(diff)
      unless exist_legacy?(diff)
        return '-'
      else
        return (legacy_notes(diff) == 0) ? '???' : sprintf('%d', legacy_notes(diff))
      end
    end

    def max_diff
      return exist?(MUSIC_DIFF_UNL) ? MUSIC_DIFF_UNL : MUSIC_DIFF_MAS
    end

    def to_hash
      hash = {
        :text_id => text_id, :number => number,
        :title => title, :subtitle => subtitle, :full_title => full_title,
        :monthly => monthly?, :limited => limited, :deleted => deleted
      }
      MUSIC_DIFF_PREFIXES.keys.each do |diff|
        if exist?(diff) and !(diff == MUSIC_DIFF_UNL and unlock_unl == UNLOCK_UNL_TYPE_NEVER)
          hash[MUSIC_DIFF_PREFIXES[diff]] = {
            :level => level_to_s(diff), :notes => notes(diff),
            :has_legacy => exist_legacy?(diff),
          }
        else
          hash[MUSIC_DIFF_PREFIXES[diff]] = {
            :level => nil, :notes => nil,
          }
        end
      end

      return hash
    end

    def <=>(other)
      if number != other.number
        return number <=> other.number
      else
        return sort_key <=> other.sort_key
      end
    end
  end

  class LegacyChart < ActiveRecord::Base
    def self.last_modified(music_id=nil)
      if music_id.present?
        legacy_charts = self.where(:music_id => music_id)
      else
        legacy_charts = self
      end
      return legacy_charts.maximum(:updated_at)
    end

    def level(diff)
      return send("#{MUSIC_DIFF_PREFIXES[diff]}_level")
    end

    def notes(diff)
      return send("#{MUSIC_DIFF_PREFIXES[diff]}_notes")
    end
  end
end
