module Competitions
  module PortlandShortTrackSeries
    class Overall < Competitions::Overall
      include PortlandShortTrackSeries::Common

      def maximum_events(race)
        7
      end

      def after_calculate
        super
        MonthlyStandings.calculate! year
      end
    end
  end
end
