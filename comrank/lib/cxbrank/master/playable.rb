require 'cxbrank/site_settings'
require 'cxbrank/master/base'

module CxbRank
  module Master
    class Playable < Base
      self.abstract_class = true

      def self.find_id(text_id)
        return self.find_by(:text_id => text_id).id
      end

      def self.find_actives(without_deleted, *order)
        actives = self.where(:display => true)
        if SiteSettings.cxb_mode?
          actives = actives.where(:limited => false)
        end
        if without_deleted
          actives = actives.where('added_at <= ? and (deleted_at is null or deleted_at > ?)',
            SiteSettings.pivot_date, SiteSettings.pivot_date)
        end
        return actives.order(order)
      end

      def deleted?
        return deleted_at.present? && (deleted_at <= SiteSettings.pivot_date)
      end

      def sprintf_for_level(level)
        return level == 0 ? '&ndash;' : sprintf(SiteSettings.level_format, level)
      end

      def sprintf_for_notes(notes)
        return notes == 0 ? '???' : sprintf('%d', notes)
      end
    end
  end
end
