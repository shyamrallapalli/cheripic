require 'test_helper'

class CheripicTest < Minitest::Test

  def test_module_has_version_number
    refute_nil ::Cheripic::VERSION
  end

end
