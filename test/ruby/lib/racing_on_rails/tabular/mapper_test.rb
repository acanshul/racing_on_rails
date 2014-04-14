require_relative "../../../test_case"
require_relative "../../../../../lib/racing_on_rails/tabular/mapper"

# :stopdoc:
module RacingOnRails
  module Tabular
    class MapperTest < Ruby::TestCase
      test "numeric_custom_columns" do
        mapper = RacingOnRails::Tabular::Mapper.new([], [ 20130501 ])
        result = mock("result", custom_attribute: 3)
        mapper.map result
      end
    end
  end
end
