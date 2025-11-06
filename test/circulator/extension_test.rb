require "test_helper"

class CirculatorExtensionTest < Minitest::Test
  describe "Extension Registry" do
    # Reset extensions before each test
    before do
      Circulator.instance_variable_set(:@extensions, Hash.new { |h, k| h[k] = [] })
    end

    describe "Circulator.extensions" do
      it "returns a hash" do
        assert_kind_of Hash, Circulator.extensions
      end

      it "returns the same hash instance on multiple calls" do
        hash1 = Circulator.extensions
        hash2 = Circulator.extensions
        assert_same hash1, hash2
      end

      it "defaults to empty array for new keys" do
        assert_equal [], Circulator.extensions["NewClass:status"]
      end

      it "stores registered extensions" do
        block = proc { state :test }
        Circulator.extensions["Document:status"] << block
        assert_includes Circulator.extensions["Document:status"], block
      end
    end

    describe "Circulator.extension" do
      it "registers an extension block" do
        block = proc { state :pending }
        Circulator.extension(:Document, :status, &block)

        assert_equal 1, Circulator.extensions["Document:status"].length
        assert_equal block, Circulator.extensions["Document:status"].first
      end

      it "uses correct key format ClassName:attribute" do
        Circulator.extension(:Document, :status) { state :pending }

        assert Circulator.extensions.key?("Document:status")
      end

      it "converts class name to string" do
        Circulator.extension(:Document, :status) { state :pending }

        assert Circulator.extensions.key?("Document:status")
        refute Circulator.extensions.key?(:"Document:status")
      end

      it "converts attribute to string" do
        Circulator.extension(:Document, :status) { state :pending }

        # Should be stored as string key
        assert Circulator.extensions.key?("Document:status")
      end

      it "allows multiple extensions for same class/attribute" do
        block1 = proc { state :pending }
        block2 = proc { state :approved }

        Circulator.extension(:Document, :status, &block1)
        Circulator.extension(:Document, :status, &block2)

        extensions = Circulator.extensions["Document:status"]
        assert_equal 2, extensions.length
        assert_equal block1, extensions[0]
        assert_equal block2, extensions[1]
      end

      it "preserves extension order" do
        blocks = []
        5.times do |i|
          block = proc { state :"state_#{i}" }
          blocks << block
          Circulator.extension(:Task, :status, &block)
        end

        registered = Circulator.extensions["Task:status"]
        assert_equal blocks, registered
      end

      it "allows extensions for different attributes on same class" do
        Circulator.extension(:Document, :status) { state :pending }
        Circulator.extension(:Document, :approval_status) { state :reviewing }

        assert_equal 1, Circulator.extensions["Document:status"].length
        assert_equal 1, Circulator.extensions["Document:approval_status"].length
      end

      it "allows extensions for different classes with same attribute" do
        Circulator.extension(:Document, :status) { state :pending }
        Circulator.extension(:Task, :status) { state :todo }

        assert_equal 1, Circulator.extensions["Document:status"].length
        assert_equal 1, Circulator.extensions["Task:status"].length
      end

      it "requires a block" do
        error = assert_raises(ArgumentError) do
          Circulator.extension(:Document, :status)
        end
        assert_match(/block/i, error.message)
      end
    end

    describe "Extension isolation" do
      it "extensions for one class don't affect another" do
        Circulator.extension(:Document, :status) { state :pending }
        Circulator.extension(:Task, :status) { state :todo }

        assert_equal 1, Circulator.extensions["Document:status"].length
        assert_equal 1, Circulator.extensions["Task:status"].length
        refute_equal Circulator.extensions["Document:status"], Circulator.extensions["Task:status"]
      end
    end
  end
end
