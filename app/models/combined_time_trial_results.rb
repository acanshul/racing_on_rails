# All categories' results in a time trial by time
# Adds +combined_results+ if Time Trial Event.
# Destroy +combined_results+ if they exist, but should not
# All the calculation happens synchronously, which isn't ideal. Logic overlaps heavily with Competition as well.
class CombinedTimeTrialResults < Event
  validates_uniqueness_of :parent_id, message: "Event can only have one CombinedTimeTrialResults"
  validate { |combined_results| combined_results.combined_results.nil? }

  default_value_for :auto_combined_results, false

  def self.calculate!
    requires_combined_results_events.each do |e|
      combined_results = create_combined_results(e)
      combined_results.calculate!
    end

    (has_combined_results_events - requires_combined_results_events).each do |e|
      destroy_combined_results e
    end
  end

  def self.requires_combined_results_events
    # TODO use SQL for this
    Event.
      where(discipline: "Time Trial", auto_combined_results: true).
      select(&:time_trial_finishes?)
  end

  def self.has_combined_results_events
    Event.where("id in (select parent_id from events where type='CombinedTimeTrialResults')")
  end

  def self.destroy_combined_results(event)
    if event.combined_results
      event.combined_results.destroy_races
      event.combined_results(true).destroy
      event.combined_results = nil
    end
  end

  def self.allows_combined_results?(event)
    event.discipline == "Time Trial"
  end

  def self.create_combined_results(event)
    unless event.combined_results
      event.create_combined_results(name: "Combined")
    end
    event.combined_results
  end

  def default_bar_points
    0
  end

  def default_discipline
    "Time Trial"
  end

  def default_ironman
    false
  end

  def should_calculate?
    parent.results_updated_at &&
    (results_updated_at.nil? || parent.results_updated_at > results_updated_at) &&
    parent.time_trial_finishes?
  end

  def calculate!
    if !should_calculate?
      return false
    end

    transaction do
      destroy_races
      combined_race = races.create!(category: Category.find_or_create_by(name: "Combined"))
      parent.races.each do |race|
        race.results.each do |result|
          if result.finished_time_trial?
            combined_race.results.create!(
              person: result.person,
              team: result.team,
              time: result.time,
              category: race.category
            )
          end
        end
      end
      _results = combined_race.results.to_a.sort do |x, y|
        if x.time
          if y.time
            x.time <=> y.time
          else
            1
          end
        else
          -1
        end
      end
      place = 1
      _results.each do |result|
        result.update(place: place.to_s)
        place = place + 1
      end
    end

    true
  end
end
