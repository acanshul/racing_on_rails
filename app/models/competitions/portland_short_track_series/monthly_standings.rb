module Competitions
  module PortlandShortTrackSeries
    class MonthlyStandings < Competition
      include PortlandShortTrackSeries::Common

      MONTHS = [ 6, 7 ]

      def self.calculate!(year = Time.zone.today.year)
        ActiveSupport::Notifications.instrument "calculate.#{name}.competitions.racing_on_rails" do
          transaction do
            parent = ::WeeklySeries.year(year).where(name: parent_event_name).first

            if parent && parent.any_results_including_children?
              MONTHS.each do |month|
                month_name = Date::MONTHNAMES[month]
                standings = MonthlyStandings.find_or_create_by!(
                  parent: parent,
                  name: "#{month_name} Standings"
                )
                standings.date = Date.new(year, month)
                if standings.source_events.none?
                  standings.add_source_events
                end
                standings.set_date
                standings.save!
                standings.delete_races
                standings.create_races
                standings.calculate!
              end
            end
          end
        end
        true
      end

      def source_results_query(race)
        super.
        where("races.category_id" => categories_for(race))
      end

      def after_source_results(results, race)
        results.each do |result|
          result["multiplier"] = result["points_factor"] || 1
        end
      end

      def add_source_events
        parent.children.select { |c| source_event_in_month?(c) }.each do |source_event|
          source_events << source_event
        end
      end

      # If there's a single race in August, include it in July
      def source_event_in_month?(source_event)
        source_event.date.month == date.month || source_event.date.month > MONTHS.last
      end

      def source_events?
        true
      end

      def default_bar_points
        1
      end

      def members_only?
        false
      end
    end
  end
end
