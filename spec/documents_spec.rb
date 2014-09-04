require_relative "../spec_helper"

describe Asari do
  let(:credentials) { { secret_access_key: "secret_access_key", access_key_id: "key_id" } }
  let(:session_token) do
    "AQoDYXdzEIr//////////wEa0ANsjnI2oPiS9IxXRsuV61WNhxbW1hPNh3/0e0k+o0szVxB9zCUW6sBOsE4wjTvgLcxwcaI8W3Llqey/BRGpAgWCYRn/xvSvrIsy4aamOKuJa2Ay/AmQZIDRzllSWC/sfq+NRSfqLguvAkymUMQ9XUoJ4KknjFjrPj0ImxYPc30epoKdLRLfn6JLAB5kboLBQZwWmQpNwA7wKkFqvTUgxOaensRQ56OroMKbIC1LjbsZpS2P5S0Ch2OzuP/oGZe5Kpoq0388SOHF9RLBPu1UQVqnDaMY/t7nq+NUH/f84OXR7NYWbophYRT9u4ZfPaE/C6VKVhAwN2aerI266hyWPRDpA1vXduF/dVPIQG5rtoE0Ryuf+ZnmLhbD54bQInaBb699j0/rGVed3NLGNPvWIOc8WDD4GNPlcJmj3EoS5c79TwQQUGd+AWdF7WW9Bikvd41ghP6sJBpm471K9pyvIJ7k2kxtBWDP/dz3r"
  end

  before do
    AWS.stub_chain(:config, :credential_provider, :credentials).and_return(credentials)
    AWS.stub_chain(:config, :credential_provider, :session_token).and_return(session_token)
  end

  describe "updating the index" do
    before :each do
      @asari = Asari.new("testdomain")
      stub_const("HTTParty", double())
      HTTParty.stub(:post).and_return(fake_post_success)
      #Time.should_receive(:now).and_return(1)
    end

    context "when region is not specified" do
      it "allows you to add an item to the index using default region." do
        HTTParty.should_receive(:post).with("http://doc-testdomain.us-east-1.cloudsearch.amazonaws.com/2013-01-01/documents/batch",
          { :body => [{ "type" => "add", "id" => "1", "fields" => { :name => "fritters"}}].to_json,
            :headers => { "Content-Type" => "application/json", "Authorization" => instance_of(String),
          "X-Amz-Date" => instance_of(String), "X-Amz-Security-Token" => instance_of(String)}})

        expect(@asari.add_item("1", {:name => "fritters"})).to eq(nil)
      end
    end

    context "when region is specified" do
      before(:each) do
        @asari.aws_region = 'my-region'
      end
      it "allows you to add an item to the index using specified region." do
        HTTParty.should_receive(:post).with("http://doc-testdomain.my-region.cloudsearch.amazonaws.com/2013-01-01/documents/batch",
          { :body => [{ "type" => "add", "id" => "1", "fields" => { :name => "fritters"}}].to_json,
            :headers => { "Content-Type" => "application/json", "Authorization" => instance_of(String),
              "X-Amz-Date" => instance_of(String), "X-Amz-Security-Token" => instance_of(String) }})

        expect(@asari.add_item("1", {:name => "fritters"})).to eq(nil)
      end
    end

    it "converts Time, DateTime, and Date fields to timestamp integers for rankability" do
      date = Date.new(2012, 4, 1)
      HTTParty.should_receive(:post).with("http://doc-testdomain.us-east-1.cloudsearch.amazonaws.com/2013-01-01/documents/batch",
        { :body => [{ "type" => "add", "id" => "1", "fields" => { :time => 1333263600, :datetime => 1333238400, :date => date.to_time.to_i }}].to_json,
          :headers => { "Content-Type" => "application/json", "Authorization" => instance_of(String),
            "X-Amz-Date" => instance_of(String), "X-Amz-Security-Token" => instance_of(String) }})

      expect(@asari.add_item("1", {:time => Time.at(1333263600), :datetime => DateTime.new(2012, 4, 1), :date => date})).to eq(nil)
    end

    it "allows you to update an item to the index." do
      HTTParty.should_receive(:post).with("http://doc-testdomain.us-east-1.cloudsearch.amazonaws.com/2013-01-01/documents/batch",
        { :body => [{ "type" => "add", "id" => "1", "fields" => { :name => "fritters"}}].to_json,
          :headers => { "Content-Type" => "application/json", "Authorization" => instance_of(String),
            "X-Amz-Date" => instance_of(String), "X-Amz-Security-Token" => instance_of(String) }})

      expect(@asari.update_item("1", {:name => "fritters"})).to eq(nil)
    end

    it "converts Time, DateTime, and Date fields to timestamp integers for rankability on update as well" do
      date = Date.new(2012, 4, 1)
      HTTParty.should_receive(:post).with("http://doc-testdomain.us-east-1.cloudsearch.amazonaws.com/2013-01-01/documents/batch",
        { :body => [{ "type" => "add", "id" => "1", "fields" => { :time => 1333263600, :datetime => 1333238400, :date => date.to_time.to_i }}].to_json,
          :headers => { "Content-Type" => "application/json", "Authorization" => instance_of(String),
            "X-Amz-Date" => instance_of(String), "X-Amz-Security-Token" => instance_of(String) }})

      expect(@asari.update_item("1", {:time => Time.at(1333263600), :datetime => DateTime.new(2012, 4, 1), :date => date})).to eq(nil)
    end

    it "allows you to delete an item from the index." do
      HTTParty.should_receive(:post).with("http://doc-testdomain.us-east-1.cloudsearch.amazonaws.com/2013-01-01/documents/batch",
        { :body => [{ "type" => "delete", "id" => "1" }].to_json,
          :headers => { "Content-Type" => "application/json", "Authorization" => instance_of(String),
            "X-Amz-Date" => instance_of(String), "X-Amz-Security-Token" => instance_of(String) }})

      expect(@asari.remove_item("1")).to eq(nil)
    end

    describe "when there are internet issues" do
      before :each do
        HTTParty.stub(:post).and_raise(SocketError.new)
      end

      it "raises an exception when you try to add an item to the index" do
        expect { @asari.add_item("1", {})}.to raise_error(Asari::DocumentUpdateException)
      end

      it "raises an exception when you try to update an item in the index" do
        expect { @asari.update_item("1", {})}.to raise_error(Asari::DocumentUpdateException)
      end

      it "raises an exception when you try to remove an item from the index" do
        expect { @asari.remove_item("1")}.to raise_error(Asari::DocumentUpdateException)
      end
    end

    describe "when there are CloudSearch issues" do
      before :each do
        HTTParty.stub(:post).and_return(fake_error_response)
      end

      it "raises an exception when you try to add an item to the index" do
        expect { @asari.add_item("1", {})}.to raise_error(Asari::DocumentUpdateException)
      end

      it "raises an exception when you try to update an item in the index" do
        expect { @asari.update_item("1", {})}.to raise_error(Asari::DocumentUpdateException)
      end

      it "raises an exception when you try to remove an item from the index" do
        expect { @asari.remove_item("1")}.to raise_error(Asari::DocumentUpdateException)
      end

    end
  end
end
