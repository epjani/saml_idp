require 'builder'
require 'saml_idp/algorithmable'
require 'saml_idp/signable'
module SamlIdp
  class AssertionBuilder
    include Algorithmable
    include Signable
    attr_accessor :reference_id
    attr_accessor :issuer_uri
    attr_accessor :principal
    attr_accessor :audience_uri
    attr_accessor :saml_request_id
    attr_accessor :saml_acs_url
    attr_accessor :raw_algorithm
    attr_accessor :authn_context_classref
    attr_accessor :expiry
    attr_accessor :encryption_opts
    attr_accessor :session_expiry

    delegate :config, to: :SamlIdp

    def initialize(reference_id, issuer_uri, principal, audience_uri, saml_request_id, saml_acs_url, raw_algorithm, authn_context_classref, expiry=60*60, encryption_opts=nil, session_expiry=nil)
      self.reference_id = reference_id
      self.issuer_uri = issuer_uri
      self.principal = principal
      self.audience_uri = audience_uri
      self.saml_request_id = saml_request_id
      self.saml_acs_url = saml_acs_url
      self.raw_algorithm = raw_algorithm
      self.authn_context_classref = authn_context_classref
      self.expiry = expiry
      self.encryption_opts = encryption_opts
      self.session_expiry = session_expiry.nil? ? config.session_expiry : session_expiry
    end

    def fresh
      builder = Builder::XmlMarkup.new
      builder.Assertion xmlns: Saml::XML::Namespaces::ASSERTION,
        ID: reference_string,
        IssueInstant: now_iso,
        Version: "2.0" do |assertion|
          assertion.Issuer issuer_uri
          sign assertion
          assertion.Subject do |subject|
            subject.NameID 'test', Format: name_id_format[:name]
            subject.SubjectConfirmation Method: Saml::XML::Namespaces::Methods::BEARER do |confirmation|
              confirmation_hash = {}
              confirmation_hash[:InResponseTo] = saml_request_id unless saml_request_id.nil?
              confirmation_hash[:NotOnOrAfter] = not_on_or_after_subject
              confirmation_hash[:Recipient] = saml_acs_url

              confirmation.SubjectConfirmationData "", confirmation_hash
            end
          end
          assertion.Conditions NotBefore: not_before, NotOnOrAfter: not_on_or_after_condition do |conditions|
            conditions.AudienceRestriction do |restriction|
              restriction.Audience audience_uri
            end
          end
          authn_statement_props = {
            AuthnInstant: now_iso,
            SessionIndex: reference_string,
          }
          unless session_expiry.zero?
            authn_statement_props[:SessionNotOnOrAfter] = session_not_on_or_after
          end
          assertion.AuthnStatement authn_statement_props do |statement|
            statement.AuthnContext do |context|
              context.AuthnContextClassRef authn_context_classref
            end
          end
          if asserted_attributes
            assertion.AttributeStatement do |attr_statement|
              attr_statement.Attribute Name: 'UserInfo', NameFormat: Saml::XML::Namespaces::Formats::Attr::URI, FriendlyName: 'UserInfo' do |attribute|
                attribute.AttributeValue asserted_attributes
              end

              # attr_statement.Attribute Name: 'AccessToken' do |attribute|
              #   attribute.AttributeValue '$ps%_atbhsr723'
              # end

              # asserted_attributes.each do |friendly_name, attrs|
              #   attrs = (attrs || {}).with_indifferent_access
              #   attr_statement.Attribute Name: attrs[:name] || friendly_name,
              #     NameFormat: attrs[:name_format] || Saml::XML::Namespaces::Formats::Attr::URI,
              #     FriendlyName: friendly_name.to_s do |attr|
              #       values = get_values_for friendly_name, attrs[:getter]
              #       values.each do |val|
              #         attr.AttributeValue val.to_s
              #       end
              #     end
              # end
            end
          end
        end
    end
    alias_method :raw, :fresh
    private :fresh

    def encrypt(opts = {})
      raise "Must set encryption_opts to encrypt" unless encryption_opts
      raw_xml = opts[:sign] ? signed : raw
      require 'saml_idp/encryptor'
      encryptor = Encryptor.new encryption_opts
      encryptor.encrypt(raw_xml)
    end

    def asserted_attributes
      if principal.respond_to?(:asserted_attributes)
        principal.send(:asserted_attributes)
      elsif !config.attributes.nil? && !config.attributes.empty?
        config.attributes
      end
    end
    private :asserted_attributes

    def get_values_for(friendly_name, getter)
      result = nil
      if getter.present?
        if getter.respond_to?(:call)
          result = getter.call(principal)
        else
          message = getter.to_s.underscore
          result = principal.public_send(message) if principal.respond_to?(message)
        end
      elsif getter.nil?
        message = friendly_name.to_s.underscore
        result = principal.public_send(message) if principal.respond_to?(message)
      end
      Array(result)
    end
    private :get_values_for

    def name_id
      name_id_getter.call principal
    end
    private :name_id

    def name_id_getter
      getter = name_id_format[:getter]
      if getter.respond_to? :call
        getter
      else
        ->(principal) { principal.public_send getter.to_s }
      end
    end
    private :name_id_getter

    def name_id_format
      @name_id_format ||= NameIdFormatter.new(config.name_id.formats).chosen
    end
    private :name_id_format

    def reference_string
      "_#{reference_id}"
    end
    private :reference_string

    def now
      @now ||= Time.now.utc
    end
    private :now

    def now_iso
      iso { now }
    end
    private :now_iso

    def not_before
      iso { now - 5 }
    end
    private :not_before

    def not_on_or_after_condition
      iso { now + expiry }
    end
    private :not_on_or_after_condition

    def not_on_or_after_subject
      iso { now + 3 * 60 }
    end
    private :not_on_or_after_subject

    def session_not_on_or_after
      iso { now + session_expiry }
    end
    private :session_not_on_or_after

    def iso
      yield.iso8601
    end
    private :iso
  end
end
