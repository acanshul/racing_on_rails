require "categories"

# Senior Men, Pro/1/2, Novice Masters 45+
#
# Categories are just a simple hierarchy of names
#
# Categories are basically labels and there is no complex hierarchy. In other words, Senior Men Pro/1/2 and
# Pro/1/2 are two distinct categories. They are not combinations of Pro and Senior and Men and Cat 1
#
# +friendly_param+ is used for friendly links on BAR pages. Example: senior_men
class Category < ActiveRecord::Base
  acts_as_tree
  include ActsAsTree::Validation

  include Categories::Ability
  include Categories::Ages
  include Categories::Cleanup
  include Categories::Equipment
  include Comparable
  include Categories::FriendlyParam
  include Categories::Gender
  include Categories::NameNormalization
  include Categories::Weight
  include Export::Categories

  acts_as_list

  has_many :results
  has_many :races

  before_validation :set_friendly_param

  validates_presence_of :name
  validates_presence_of :friendly_param

  scope :same, lambda { |category|
    query = Category.all

    # if category.ability_range != (0..::Categories::MAXIMUM)
      query = query.where(ability_begin: category.ability_range)
    # end

    # if category.ages != (0..::Categories::MAXIMUM)
      query = query.where(ages_begin: category.ages)
    # end

    # if category.equipment
      query = query.where(equipment: category.equipment)
    # end

    if category.gender != "M"
      query = query.where(gender: category.gender)
    end

    # if category.weight
      query = query.where(weight: category.weight)
    # end

    query
  }

  scope :different, lambda { |category, other_category|
    query = Category.all

    if category.ability_range != (0..::Categories::MAXIMUM) && other_category.ability_range != (0..::Categories::MAXIMUM) && category.gender != "M"
      query = query.where.not(gender: category.gender)
    end

    # if category.ability_range != (0..::Categories::MAXIMUM) && !category.ability_range.include?(other_category.ability_begin)
    #   query = query.where.not(ability_begin: category.ability_range)
    # end
    #
    # if category.ages != (0..::Categories::MAXIMUM) && !category.ages.include?(other_category.ages_begin)
    #   query = query.where.not(ages_begin: category.ages)
    # end
    #
    # if category.equipment != other_category.equipment
    #   query = query.where.not(equipment: category.equipment)
    # end
    #
    # if category.gender != other_category.gender
    #   query = query.where.not(gender: category.gender)
    # end
    #
    # if category.weight != other_category.weight
    #   query = query.where.not(weight: category.weight)
    # end

    query
  }

  def all_abilities?
    ability_range == (0..::Categories::MAXIMUM)
  end

  def all_ages?
    ages == (0..::Categories::MAXIMUM)
  end

  def all_equipment?
    equipment
  end

  def all_genders?
    gender == "M"
  end

  def all_weights?
    weight
  end

  scope :within, lambda { |race|
    # TODO match by ages for masters
    # TODO all_ages? all_juniors?
    # TODO Need to handle these as overlapping ranges in different tracks: junior, masters, equipment
    # TODO USe betweeen
    # TODO handle no groups
    # TODO other_event_categories should be a method?

    # What groups does a category have?
    # * ability + gender: cat 3 Men, cat 3 women (gender becasue there are two cats with same ability and different genders)
    # * gender: senior Men
    # * age + gender: junior men, jr Women
    # * equipment: singlespeed
    # * weight: Clydesdale



    within = same(race.category)

    other_event_categories = race.event.categories.reject { |category| category == race.category }

    other_event_categories.each do |category|
      within = within.different(category, race.category)
    end

    within
  }

  # All categories with no parent (except root 'association' category)
  def self.find_all_unknowns
   Category.includes(:children).where(parent_id: nil).where("name != ?", RacingAssociation.current.short_name)
  end

  # Sr, Mst, Jr, Cat, Beg, Exp
  def self.short_name(name)
    return name if name.blank?
    name.gsub('Senior', 'Sr').gsub('Masters', 'Mst').gsub('Junior', 'Jr').gsub('Category', 'Cat').gsub('Beginner', 'Beg').gsub('Expert', 'Exp').gsub("Clydesdale", "Clyd")
  end

  def name=(value)
    self[:name] = Category.normalized_name(value)
  end

  def raw_name
    name
  end

  def raw_name=(value)
    self[:name] = value
  end

  # Sr, Mst, Jr, Cat, Beg, Exp
  def short_name
    Category.short_name name
  end

  # Compare by position, then by name
  def <=>(other)
    return -1 if other.nil?
    return super unless other.is_a?(Category)
    return 0 if self[:id] && self[:id] == other[:id]
    diff = (position <=> other.position)
    if diff == 0
      name <=> other.name
    else
      diff
    end
  end

  def to_s
    "#<Category #{id} #{parent_id} #{position} #{name}>"
  end
end
