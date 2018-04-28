require 'builder'
module SamlIdp
  class ResponseBuilder
    include Signable
    include Algorithmable

    attr_accessor :response_id
    attr_accessor :issuer_uri
    attr_accessor :saml_acs_url
    attr_accessor :saml_request_id
    attr_accessor :assertion_and_signature
    attr_accessor :algorithm

    def initialize(response_id, issuer_uri, saml_acs_url, saml_request_id, assertion_and_signature, algorithm)
      self.response_id = response_id
      self.issuer_uri = issuer_uri
      self.saml_acs_url = saml_acs_url
      self.saml_request_id = saml_request_id
      self.assertion_and_signature = assertion_and_signature
      self.algorithm = algorithm
    end

    def encoded
      @encoded ||= encode
    end

    def raw
      build
    end

    def encode
      Base64.strict_encode64(signed)
    end
    private :encode

    def build
      resp_options = {}
      resp_options[:ID] = response_id_string
      resp_options[:Version] =  "2.0"
      resp_options[:IssueInstant] = now_iso
      resp_options[:Destination] = saml_acs_url
      resp_options[:Consent] = Saml::XML::Namespaces::Consents::UNSPECIFIED
      resp_options[:InResponseTo] = saml_request_id unless saml_request_id.nil?
      resp_options["xmlns:samlp"] = Saml::XML::Namespaces::PROTOCOL
      resp_options["xmlns:saml"] = "urn:oasis:names:tc:SAML:2.0:assertion"

      builder = Builder::XmlMarkup.new
      generated_reference_id do
        builder.tag! "samlp:Response", resp_options do |response|
          response.Issuer issuer_uri, xmlns: Saml::XML::Namespaces::ASSERTION
          sign response
          response.tag! "samlp:Status" do |status|
            status.tag! "samlp:StatusCode", Value: Saml::XML::Namespaces::Statuses::SUCCESS
          end
          response << assertion_and_signature
        end
      end
    end
    private :build

    def reference_id
      response_id
    end

    def response_id_string
      "_#{response_id}"
    end
    private :response_id_string

    def now_iso
      Time.now.utc.iso8601
    end
    private :now_iso
  end
end
