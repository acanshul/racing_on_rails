module CreateIfBestResultForRaceExtension
  def create_if_best_result_for_race(attributes)
    source_result = attributes[:source_result]
    scores = proxy_association.owner.scores
    scores.each do |score|
      same_race  = (score.source_result.race_id  == source_result.race_id)
      same_person = (score.source_result.person_id == source_result.person_id)
      if same_race && score.source_result.person && same_person
        if attributes[:points] > score.points
          scores.delete score
        else
          return nil
        end
      end
    end
    create attributes
  end
end

# Race result
#
# Race is the only required attribute -- even +person+ and +place+ can be blank
#
# Result keeps its own copy of +number+ and +team+, even though each Person has
# a +team+ atribute and many RaceNumbers. Result's number is just a String, not
# a RaceNumber
class Result < ActiveRecord::Base
  before_save :set_associated_records

  include Results::Caching
  include Results::Cleanup
  include Results::Comparison
  include Results::Competitions
  include Results::CustomAttributes
  include Results::Times
  include Export::Results

  after_save :update_person_number
  after_destroy :destroy_people
  after_destroy :destroy_teams

  belongs_to :category
  belongs_to :event
  belongs_to :race
  belongs_to :person
  belongs_to :team

  validates_presence_of :race

  scope :person_event, lambda { |person, event|
    includes(scores: [ :source_result, :competition_result ]).
    where(event: event).
    where(person: person)
  }

  scope :team_event, lambda { |team, event|
    includes(scores: [ :source_result, :competition_result ]).
    where("results.event_id" => event.id).
    where(team_id: team.id)
  }

  scope :person, lambda { |person|
    if person.is_a? Person
      person_id = person.id
    else
      person_id = person
    end

    includes(:team, :person, :scores, :category, { race: [ :event, :category ] }).
    where(person_id: person_id)
  }

  attr_accessor :updated_by

  # Replace any new +person+, or +team+ with one that already exists if name matches
  # TODO rationalize names
  def set_associated_records
    return true if competition_result?

    set_person
    update_membership
    set_team

    true
  end

  def set_person
    if person && person.new_record?
      person.updated_by = event
      if person.name.blank?
        self.person = nil
      else
        existing_people = find_people
        if existing_people.size == 1
          self.person = existing_people.first
        elsif existing_people.size > 1
          self.person = Person.select_by_recent_activity(existing_people)
        end
      end
    end
  end

  def set_team
    if team && team.new_record?
      team.updated_by = event
      if team.name.blank?
        self.team = nil
      else
        existing_team = Team.find_by_name_or_alias(team.name)
        self.team = existing_team if existing_team
      end
    end
  end

  # Use +first_name+, +last_name+, +race_number+, +team+ to figure out if +person+ already exists.
  # Returns an Array of People if there is more than one potential match
  #
  # TODO refactor into methods or split responsibilities with Person?
  # Need Event to match on race number. Event will not be set before result is saved to database
  def find_people
    matches = Set.new

    #license first if present and source is reliable (USAC)
    if RacingAssociation.current.eager_match_on_license? && license.present?
      matches = matches + Person.where(license: license)
      return matches if matches.size == 1
    end

    # name
    matches = matches + Person.find_all_by_name_or_alias(first_name: first_name, last_name: last_name)
    return matches if matches.size == 1

    # number
    if number.present?
      if matches.size > 1
        # use number to choose between same names
        RaceNumber.find_all_by_value_and_event(number, event).each do |race_number|
          if matches.include?(race_number.person)
            return [ race_number.person ]
          end
        end
      elsif name.blank?
        # no name, so try to match by number
        matches = RaceNumber.find_all_by_value_and_event(number, event).map(&:person)
      end
    end

    # team
    unless team_name.blank?
      team = Team.find_by_name_or_alias(team_name)
      matches.reject! do |match|
        match.team != team
      end
      return matches if matches.size == 1
    end

    # license
    unless self.license.blank?
      matches.reject! do |match|
        match.license != license
      end
    end

    matches
  end

  def update_membership
    if update_membership?
      person.updated_by = event
      person.member_from = race.date
    end
  end

  def update_membership?
    person &&
    RacingAssociation.current.add_members_from_results? &&
    person.new_record? &&
    person.first_name.present? &&
    person.last_name.present? &&
    person[:member_from].blank? &&
    event.association? &&
    !RaceNumber.rental?(number, Discipline[event.discipline])
  end

  # Set +person#number+ to +number+ if this isn't a rental number
  # FIXME optimize default number issuer business
  def update_person_number
    return true if competition_result?

    discipline = Discipline[event.discipline]
    default_number_issuer = NumberIssuer.find_by_name(RacingAssociation.current.short_name)
    if person && event.number_issuer && event.number_issuer != default_number_issuer && number.present? && !RaceNumber.rental?(number, discipline)
      person.updated_by = updated_by
      person.add_number(number, discipline, event.number_issuer, event.date.year)
    end
  end

  # Destroy People that only exist because they were created by importing results
  def destroy_people
    if person && person.results.count == 0 && person.created_from_result? && !person.updated_after_created?
      person.destroy
    end
  end

  # Destroy Team that only exist because they were created by importing results
  def destroy_teams
    if team && team.results.count == 0 && team.people.count == 0 && team.created_from_result? && !team.updated_after_created?
      team.destroy
    end
  end

  # Only used for manual entry of Cat 4 Womens Series Results
  def validate_person_name
    if first_name.blank? && last_name.blank?
      errors.add(:first_name, "and last name cannot both be blank")
    end
  end

  def category_name=(name)
    if name.blank?
      self.category = nil
    else
      self.category = Category.find_or_create_by_normalized_name(name)
    end
    self[:category_name] = name.try(:to_s)
  end

  # TODO Cache this, too
  def team_size
    if race_id
      @team_size ||= Result.where(race_id: race_id, place: place).count
    else
      @team_size ||= 1
    end
  end

  # Not blank, DNF, DNS, DQ.
  def finished?
    return false if place.blank?
    return false if ["DNF", "DNS", "DQ"].include?(place)
    numeric_place?
  end

  def finished_time_trial?
    numeric_place? && time && time > 0
  end

  # Does this result belong to the last event in a MultiDayEvent?
  def last_event?
    return false unless self.event && event.parent
    return false unless event.parent.respond_to?(:parent)
    return true unless event.parent

    !(event.parent && (event.parent.end_date != self.date))
  end

  def date
    self[:date] || race.try(:date)
  end

  def distance
    race && race.distance
  end

  def event_id
    self[:event_id] || (race || race(true)).try(:event_id)
  end

  def event(reload = false)
    if race(reload)
      race.event(reload)
    end
  end

  def laps
    self[:laps] || (race && race.laps)
  end

  def place
    self[:place] || ''
  end

  def points
    if self[:points]
      self[:points].to_f
    else
      0.0
    end
  end

  # Hot spots
  def points_bonus_penalty=(value)
    if value == nil || value == ""
      value = 0
    end
    write_attribute(:points_bonus_penalty, value)
  end

  # Points from placing at finish, not from hot spots
  def points_from_place=(value)
    if value == nil || value == ""
      value = 0
    end
    write_attribute(:points_from_place, value)
  end

  def first_name=(value)
    if self.person
      self.person.first_name = value
    else
      self.person = Person.new(first_name: value)
    end
    self[:first_name] = value
    self[:name] = self.person.try(:name, date)
  end

  def last_name=(value)
    if self.person
      self.person.last_name = value
    else
      self.person = Person.new(last_name: value)
    end
    self[:last_name] = value
    self[:name] = self.person.try(:name, date)
  end

  def person_name
    name
  end

  # person.name
  def name=(value)
    if value.present?
      if person.try(:name) != value
        self.person = Person.new(name: value)
      end
      self[:first_name] = person.first_name
      self[:last_name] = person.last_name
    else
      self.person = nil
      self[:first_name] = nil
      self[:last_name] = nil
    end
    self[:name] = value
  end

  def person_name=(value)
    self.name = value
  end

  # Person's current team name
  def person_team_name
    if person
      person.team_name
    else
      ""
    end
  end

  def team_name=(value)
    team_id_will_change!
    if team.nil? || team.name != value
      self.team = Team.new(name: value)
    end
    if person && person.team_name != value
      person.team = team
    end
    self[:team_name] = value
  end

  def member_result?
    (person_id.nil? || (person_id && person.member?(date))) && !non_members_on_team?
  end

  def non_members_on_team?
    exempt_cats = RacingAssociation.current.exempt_team_categories
    if exempt_cats.nil? || exempt_cats.include?(race.category.name)
      return false
    end

    non_members = false

    other_results_in_place = Result.where(race_id: race_id, place: place)
    other_results_in_place.each do |result|
      unless result.person.nil?
        if !result.person.member?(date)
          self.update_attribute members_only_place: ""
          non_members = true
        end
      end
    end

    non_members
  end

  def numeric_place?
    place && place.to_i > 0
  end

  def numeric_place
    if numeric_place?
      place.to_i
    else
      0
    end
  end

  def next_place
    if numeric_place?
      numeric_place + 1
    else
      place
    end
  end

  def inspect_debug
    puts to_long_s
    scores(true).sort.each do |score|
      puts score
    end
  end

  # Add +race+ and +race#event+ name, time and points to default to_s
  def to_long_s
    "#<Result #{id}\t#{place}\t#{race.event.name}\t#{race.name} (#{race.id})\t#{name}\t#{team_name}\t#{self.category_name}\t#{points}\t#{time_s if self[:time]}>"
  end

  def to_s
    "#<Result #{id} place #{place} race #{race_id} person #{person_id} team #{team_id} pts #{points}>"
  end
end
