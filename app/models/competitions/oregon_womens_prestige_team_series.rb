class OregonWomensPrestigeTeamSeries < Competition
  include Concerns::Competition::CalculatorAdapter
  
  def friendly_name
    "Oregon Womens Prestige Team Series"
  end
  
  def category_names
    [ "Team" ]
  end
  
  # Decreasing points to 20th place, then 2 points for 21st through 100th
  def point_schedule
    [ 100, 80, 70, 60, 55, 50, 45, 40, 35, 30, 25, 20, 18, 16, 14, 12, 10, 8, 6, 4 ] + ([ 2 ] * 80)
  end
  
  def source_events?
    true
  end
  
  def source_events
    (OregonWomensPrestigeSeries.find_for_year(year) || OregonWomensPrestigeSeries.create).source_events
  end

  def categories?
    true
  end

  def results_per_event
    3
  end

  def use_source_result_points?
    false
  end

  # source_results must be in person, place ascending order
  # "Universal" results usable by all competitions once they use Calculator
  # TODO Use person_id and team_id
  def source_results(race = nil)
    query = Result.
      select([
        "bar",
        "coalesce(races.bar_points, events.bar_points, parents_events.bar_points, parents_events_2.bar_points) as multiplier",
        "events.date",
        "events.ironman",
        "events.sanctioned_by",
        "events.type",
        "people.date_of_birth",
        "people.member_from",
        "people.member_to",
        "place",
        "points",
        "races.category_id",
        "race_id",
        "results.event_id",
        "results.id as id", 
        "results.team_id as participant_id",
        "year"
      ]).
      joins(:race => :event).
      joins("left outer join people on people.id = results.person_id").
      joins("left outer join events parents_events on parents_events.id = events.parent_id").
      joins("left outer join events parents_events_2 on parents_events_2.id = parents_events.parent_id").
      where("year = ?", year)

    # Only consider results from a set of source events
    if source_events? && source_events.present?
      query = query.where("results.event_id in (?)", source_events.map(&:id))
    end
    
    # Only consider results with categories that match +race+'s category
    if categories?
      query = query.where("races.category_id in (?)", category_ids_for(race))
    end
    
    Result.connection.select_all query
  end

  def category_ids_for(race)
    categories = Category.where("name in (?)", OregonWomensPrestigeSeries.find_for_year.category_names).all
    categories.map(&:id) + categories.map(&:descendants).to_a.flatten.map(&:id)
  end

  def create_competition_results_for(results, race)
    results.each do |result|
      competition_result = Result.create!(
        :place              => result.place,
        :team_id            => result.participant_id,
        :event              => self,
        :race               => race,
        :competition_result => true,
        :team_competition_result => true,
        :points             => result.points
      )
       
      result.scores.each do |score|
        create_score competition_result, score.source_result_id, score.points
      end
    end

    true
  end
end
