require_relative "../spec_helper"

describe Asari do
  let(:credentials) { { secret_access_key: "secret_access_key", access_key_id: "key_id" } }

  before :each do
    @asari = Asari.new("testdomain")
    stub_const("HTTParty", double())
    HTTParty.stub(:get).and_return(fake_response)
    AWS.stub_chain(:config, :credential_provider, :credentials).and_return(credentials)
  end

  describe "searching" do
    context "when region is not specified" do
      it "allows you to search using default region." do
        HTTParty.should_receive(:get).with("http://search-testdomain.us-east-1.cloudsearch.amazonaws.com/2013-01-01/search?q=testsearch&size=10", instance_of(Hash))
        @asari.search("testsearch")
      end
    end

    context "when region is not specified" do
      before(:each) do
        @asari.aws_region = 'my-region'
      end
      it "allows you to search using specified region." do
        HTTParty.should_receive(:get).with("http://search-testdomain.my-region.cloudsearch.amazonaws.com/2013-01-01/search?q=testsearch&size=10", instance_of(Hash))
        @asari.search("testsearch")
      end
    end

    it "escapes dangerous characters in search terms." do
      HTTParty.should_receive(:get).with("http://search-testdomain.us-east-1.cloudsearch.amazonaws.com/2013-01-01/search?q=testsearch%21&size=10", instance_of(Hash))
      @asari.search("testsearch!")
    end

    it "honors the page_size option" do
      HTTParty.should_receive(:get).with("http://search-testdomain.us-east-1.cloudsearch.amazonaws.com/2013-01-01/search?q=testsearch&size=20", instance_of(Hash))
      @asari.search("testsearch", :page_size => 20)
    end

    it "honors the page option" do
      HTTParty.should_receive(:get).with("http://search-testdomain.us-east-1.cloudsearch.amazonaws.com/2013-01-01/search?q=testsearch&size=20&start=40", instance_of(Hash))
      @asari.search("testsearch", :page_size => 20, :page => 3)
    end

    describe "the sort option" do
      it "takes an array with :asc" do
        HTTParty.should_receive(:get).with("http://search-testdomain.us-east-1.cloudsearch.amazonaws.com/2013-01-01/search?q=testsearch&size=10&sort=some_field%20asc", instance_of(Hash))
        @asari.search("testsearch", :sort => ["some_field", :asc])
      end

      it "takes an array with :desc" do
        HTTParty.should_receive(:get).with("http://search-testdomain.us-east-1.cloudsearch.amazonaws.com/2013-01-01/search?q=testsearch&size=10&sort=some_field%20desc", instance_of(Hash))
        @asari.search("testsearch", :sort => ["some_field", :desc] )
      end

      it "sort ascending by default" do
        HTTParty.should_receive(:get).with("http://search-testdomain.us-east-1.cloudsearch.amazonaws.com/2013-01-01/search?q=testsearch&size=10&sort=some_field%20asc", instance_of(Hash))
        @asari.search("testsearch", :sort => ["some_field"])
      end
    end

    it "returns a list of document IDs for search results." do
      result = @asari.search("testsearch")

      expect(result.size).to eq(2)
      expect(result[0]).to eq("123")
      expect(result[1]).to eq("456")
      expect(result.total_pages).to eq(1)
      expect(result.current_page).to eq(1)
      expect(result.page_size).to eq(10)
      expect(result.total_entries).to eq(2)
    end

    it "returns an empty list when no search results are found." do
      HTTParty.stub(:get).and_return(fake_empty_response)
      result = @asari.search("testsearch")
      expect(result.size).to eq(0)
      expect(result.total_pages).to eq(1)
      expect(result.current_page).to eq(1)
      expect(result.total_entries).to eq(0)
    end

    context 'return_fields option' do
      let(:response_with_field_data) {  OpenStruct.new(:parsed_response => { "hits" => {
        "found" => 2,
        "start" => 0,
        "hit" => [{"id" => "123",
          "fields" => {"name" => "Beavis", "address" => "arizona"}},
          {"id" => "456",
            "fields" => {"name" => "Honey Badger", "address" => "africa"}}]}},
            :response => OpenStruct.new(:code => "200"))
      }
      let(:return_struct) {{"123" => {"name" => "Beavis", "address" => "arizona"},
                           "456" => {"name" => "Honey Badger", "address" => "africa"}}}

      before :each do
        HTTParty.should_receive(:get).with("http://search-testdomain.us-east-1.cloudsearch.amazonaws.com/2013-01-01/search?q=testsearch&size=10&return=name,address", instance_of(Hash)).and_return response_with_field_data
      end

      subject { @asari.search("testsearch", :return_fields => [:name, :address])}
      it {should eql return_struct}
    end

    it "raises an exception if the service errors out." do
      HTTParty.stub(:get).and_return(fake_error_response)
      expect { @asari.search("testsearch)") }.to raise_error Asari::SearchException
    end

    it "raises an exception if there are internet issues." do
      HTTParty.stub(:get).and_raise(SocketError.new)
      expect { @asari.search("testsearch)") }.to raise_error Asari::SearchException
    end

  end

  describe "boolean searching" do
    it "builds a query string from a passed hash" do
      HTTParty.should_receive(:get).with("http://search-testdomain.us-east-1.cloudsearch.amazonaws.com/2013-01-01/search?q=&fq=(and%20foo:'bar'baz:'bug')&size=10", instance_of(Hash))
      @asari.search(filter: { and: { foo: "bar", baz: "bug" }})
    end

    it "honors the logic types" do
      HTTParty.should_receive(:get).with("http://search-testdomain.us-east-1.cloudsearch.amazonaws.com/2013-01-01/search?q=&fq=(or%20foo:'bar'baz:'bug')&size=10", instance_of(Hash))
      @asari.search(filter: { or: { foo: "bar", baz: "bug" }})
    end

    it "supports nested logic" do
      HTTParty.should_receive(:get).with("http://search-testdomain.us-east-1.cloudsearch.amazonaws.com/2013-01-01/search?q=&fq=(or%20is_donut:'true'(and%20round:'true'frosting:'true'fried:'true'))&size=10", instance_of(Hash))
      @asari.search(filter: { or: { is_donut: true, and:
                            { round: true, frosting: true, fried: true }}
      })
    end

    it "fails gracefully with empty params" do
      HTTParty.should_receive(:get).with("http://search-testdomain.us-east-1.cloudsearch.amazonaws.com/2013-01-01/search?q=&fq=(or%20is_donut:'true')&size=10", instance_of(Hash))
      @asari.search(filter: { or: { is_donut: true, and:
                            { round: "", frosting: nil, fried: nil }}
      })
    end

    it "supports full text search and boolean searching" do
      HTTParty.should_receive(:get).with("http://search-testdomain.us-east-1.cloudsearch.amazonaws.com/2013-01-01/search?q=nom&fq=(or%20is_donut:'true'(and%20fried:'true'))&size=10", instance_of(Hash))
      @asari.search("nom", filter: { or: { is_donut: true, and:
                                   { round: "", frosting: nil, fried: true }}
      })
    end
  end

  describe "geography searching" do
    it "builds a proper query string" do
      box = Asari::Geography.coordinate_box(meters: 5000, lat: 45.52, lng: 122.6819)
      HTTParty.should_receive(:get).with("http://search-testdomain.us-east-1.cloudsearch.amazonaws.com/2013-01-01/search?q=&fq=(and%20%28range+field%3Dlat+%5B2505771415%2C+2506771417%5D%29%28range+field%3Dlng+%5B2358260777%2C+2359261578%5D%29)&size=10", instance_of(Hash))
      @asari.search filter: { and: box }
    end
  end

  describe "searching with facets" do
    it "builds a proper query string if one facet in array is passed" do
      expected_url = "http://search-testdomain.us-east-1.cloudsearch.amazonaws.com/2013-01-01/" +
        "search?q=&facet.genres=%7B%7D&size=10"
      HTTParty.should_receive(:get).with(expected_url, instance_of(Hash))
      @asari.search(facet: [:genres])
    end

    it "builds a proper query string if many facets in array is passed" do
      expected_url = "http://search-testdomain.us-east-1.cloudsearch.amazonaws.com/2013-01-01/" +
        "search?q=&facet.genres=%7B%7D&facet.year=%7B%7D&size=10"
      HTTParty.should_receive(:get).with(expected_url, instance_of(Hash))
      @asari.search(facet: [:genres, :year])
    end

    it "builds a proper query string if one facet with options is passed" do
      expected_url = "http://search-testdomain.us-east-1.cloudsearch.amazonaws.com/2013-01-01/search?q=&facet.genres=%7Bsort%3A%27count%27%2Csize%3A5%7D&size=10"

      HTTParty.should_receive(:get).with(expected_url, instance_of(Hash))
      @asari.search(facet: { genres: { sort: "count", size: 5 } })
    end
  end
end
