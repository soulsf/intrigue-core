module Intrigue
module Ident
class Cpe

  include Intrigue::Task::Web

  def initialize(cpe_string)
    @cpe = cpe_string
    x = _parse_cpe(@cpe)

    return nil unless x

    @vendor = x[:vendor]
    @product = x[:product]
    @version = x[:version]
    @variant = x[:variant] # TODO... currenty not used

  end

  def vulns
    query_intrigue_vulndb_api
  end

  def query_intrigue_vulndb_api

    #puts "Querying VulnDB API!"
    #puts "https://intrigue.io/api/vulndb/match/#{@vendor}/#{@product}/#{@version}"
    begin
      response = http_request :get, "https://intrigue.io/api/vulndb/match/#{Uri.escape(@vendor)}/#{Uri.escape(@product)}/#{Uri.escape(@version)}"
      result = JSON.parse(response.body)
      # return our normal hash
      out = result.map do |x|
        vuln = {
          cve_id: x,
          cwe_id: nil,
          cvss_v2: {score: nil, vector: nil },
          cvss_v3: {score: nil, vector: nil }
        }
      end
    rescue Json::ParserError =>e
    end
  out
  end

  # hacktastic! matches vulns by CPE
  def query_local_nvd_json

    # Set a data directory underneath our folder if we're not in the context of core
    if $intrigue_basedir
      nvd_data_directory = "#{$intrigue_basedir}/data/nvd"
    else
      nvd_data_directory = "#{File.expand_path('data/nvd', File.dirname(__FILE__))}"
    end

    # fail unless we have something to match
    return [] unless @version

    vulns = []
    matched = []
    files = [
        "#{nvd_data_directory}/nvdcve-1.0-2018.json",
        "#{nvd_data_directory}/nvdcve-1.0-2017.json",
        "#{nvd_data_directory}/nvdcve-1.0-2016.json"
      ]

    files.each do |file|
      #puts "DEBUG Checking file: #{f}"
      next unless File.exist? file

      # open and read the file
      f = File.open(file,"r")
      parser = Yajl::Parser.new
      json = parser.parse(f)

      # free memory
      parser = nil
      f.close

      json["CVE_Items"].each do |v|

        # Note that the JSON has CVE stuff under a hash, so
        # pull that out separately (probably due to NVD responsibility vs Mitre)

        # data sanity check
        unless v["cve"]["affects"] && v["cve"]["affects"]["vendor"] && v["cve"]["affects"]["vendor"]["vendor_data"]
          #puts "DEBUG No Affects data... #{v["cve"]}"
          next
        end

        # check to make sure it includes our vendor
        vendors = v["cve"]["affects"]["vendor"]["vendor_data"].map{|x| x["vendor_name"].downcase }
        next unless vendors.uniq.include? @vendor.downcase

        # iterate through the heirarchy to get to product and version we can match on
        v["cve"]["affects"]["vendor"]["vendor_data"].each do |vd|
          next if matched.include? v["cve"]["CVE_data_meta"]["ID"] # skip if we got it already

          #puts "DEBUG Checking Vendor Data #{vd}"
          vd["product"]["product_data"].each do |p|
            next if matched.include? v["cve"]["CVE_data_meta"]["ID"] # skip if we got it already

            #puts "DEBUG Checking product #{p}"
            p["version"]["version_data"].each do |vd|
              next if matched.include? v["cve"]["CVE_data_meta"]["ID"] # skip if we got it already
              next unless p["product_name"].downcase == @product.downcase
              #puts "DEBUG Matching: #{vd["version_value"]} with #{@version}"

              # first make sure we share the same major version
              next unless  vd["version_value"].split(".").first == @version.split(".").first

              # if so, check that this affects versions equal to or newer than uors
              vuln_version = Versionomy.parse(vd["version_value"])
              our_version = Versionomy.parse(@version)

              if vuln_version >= our_version
                #puts "DEBUG - VULN MATCHED (#{v["cve"]['CVE_data_meta']['ID']}): #{Versionomy.parse(vd['version_value'])} >= #{Versionomy.parse(@version)}}!"
                matched << v["cve"]["CVE_data_meta"]["ID"]
                cve_id = v["cve"]["CVE_data_meta"]["ID"]
                #puts "CVE: #{cve_id}"

                # Get the CWE if we have it
                if v["cve"]["problemtype"] && v["cve"]["problemtype"]["problemtype_data"].first
                  cwe_id = v["cve"]["problemtype"]["problemtype_data"].first["description"].first["value"]
                  #puts "CWE: #{cwe_id}"
                end

                # Get the CVSS data if we have it
                if v["impact"]
                  cvss_v2_score = v["impact"]["baseMetricV2"]["cvssV2"]["baseScore"]
                  cvss_v2_vector = v["impact"]["baseMetricV2"]["cvssV2"]["vectorString"]
                  #puts "CVSS v2: #{cvss_v2}"

                  # v3 only goes back to 2016
                  if v["impact"]["baseMetricV3"]
                    cvss_v3_score = v["impact"]["baseMetricV3"]["cvssV3"]["baseScore"]
                    cvss_v3_vector = v["impact"]["baseMetricV3"]["cvssV3"]["vectorString"]
                    #puts "CVSS v3: #{cvss_v3}"
                  end
                end

                # create a hash with the vuln's data
                vuln = {
                  cve_id: cve_id,
                  cwe_id: cwe_id,
                  cvss_v2: {score: cvss_v2_score, vector: cvss_v2_vector },
                  cvss_v3: {score: cvss_v3_score, vector: cvss_v3_vector }
                }

                #puts "DEBUG Vuln: #{vuln}"
                vulns << vuln
              end

            end
          end
        end
      end
    end

    #puts "DEBUG Sending #{vulns.uniq.count} vulns"
    json = nil

  vulns.uniq
  end

  private

  def _parse_cpe(string)

    m = string.match(/^cpe:2.3:[o|a|s|h]:(.*?):.*$/)
    vendor = m[1] if m
    #puts "DEBUG Got Vendor: #{vendor}"
    m = string.match(/^cpe:2.3:[o|a|s|h]:.*?:(.*?):.*$/)
    product = m[1] if m
    #puts "DEBUG Got Product: #{product}"
    m = string.match(/^cpe:2.3:[o|a|s|h]:.*?:.*?:(.*)$/)
    version = m[1] if m
    #puts "DEBUG Got Version: #{version}"

    # if version has parens, only use the stuff priior (apache, nginx, etc)
    if version =~ /\(/
      old_version = version
      #puts "DEBUG Splitting Version: #{version}"

      version = old_version.split("(").first.chomp
      #puts "DEBUG New Version: #{version}"

      variant = old_version.split("(").last.split(")").first.chomp  #HACK
      #puts "DEBUG New Variant: #{variant}"

    end

    # if there's nothing to do here...
    return unless product && vendor && version

    # HACK... cleanup version if needed
    version = version.gsub(/\(.*/,"").gsub(/\+.*/,"").gsub(/-.*/,"").gsub(/\s.*/,"")

    parsed = {
      :vendor => vendor,
      :product => product,
      :version => version,
      :variant => variant
    }

  parsed
  end

end

end
end
