require 'estraierpure_ext'
require 'rexml/document'

module ActsAsEstraierDoc
  def self.included(base)
    base.extend ActMethods
  end

  module ActMethods
    def acts_as_estraier_doc(options = {})
      self.extend ClassMethods
      send :include, ActsAsEstraierDoc::InstanceMethods
      send :alias_method_chain, :to_xml,  :estdoc
      send :alias_method_chain, :to_json, :estdoc
      send :attr_accessor, :estdoc
      send :attr_accessor, :skip_update_est_index

      cattr_accessor :configuration, :estraier_conn

      self.configuration = {
        :condition_options => EstraierPure::Condition::SIMPLE,
        :depth             => 0,
      }
      self.configuration.update(options) if options.is_a? Hash
      self.configuration[:node][:host] = 'localhost' unless self.configuration[:node].include? :host
      self.configuration[:node][:port] = 1978        unless self.configuration[:node].include? :port

      self.estraier_conn = EstraierPure::Node::new
      self.estraier_conn.set_url("http://#{self.configuration[:node][:host]}:#{self.configuration[:node][:port]}/node/#{self.configuration[:node][:node]}")
      self.estraier_conn.set_auth(self.configuration[:node][:user], self.configuration[:node][:pass])

      after_save     :update_est_index
      before_destroy :remove_est_index
    end
  end

  module ClassMethods
    HINT_KEYS = ['HIT', 'DOCNUM', 'WORDNUM', 'TIME']

    def est_search(phrase, options = {})
      cond = EstraierPure::Condition::new
      condition_options = 0
      if options.include? :condition_options
        options[:condition_options].to_a.each do |condition_option|
          condition_options = condition_options | condition_option
        end
      else
        condition_options = self.configuration[:condition_options]
      end
      cond.set_options(condition_options)
      cond.set_phrase(phrase.to_s)
      options[:attributes].to_a.each { |attribute| cond.add_attr(attribute) } if options.include? :attributes
      cond.set_max(options[:limit])   if options.include? :limit
      cond.set_skip(options[:offset]) if options.include? :offset
      cond.set_order(options[:order]) if options.include? :order
      wwidth = options.include?(:snippet_wwidth) ? options[:snippet_wwidth] : 480
      hwidth = options.include?(:snippet_hwidth) ? options[:snippet_hwidth] : -1
      awidth = options.include?(:snippet_awidth) ? options[:snippet_awidth] : -1
      self.estraier_conn.set_snippet_width(wwidth, hwidth, awidth)
      Rails.logger.info cond.inspect if options[:debug]

      result = {:records => [], :info => {}}
      rs = self.estraier_conn.search(cond, options.include?(:depth) ? options[:depth] : 0)
      if rs
        docs = {}
        ids  = []
        rs.each do |doc|
          docs[doc.attr('record_id').to_i] = doc
          ids << doc.attr('record_id').to_i
        end
        records = self.find :all, :conditions => {:id => ids}, :include => options[:include]
        (ids - records.map(&:id)).each do |orphaned_id|
          Rails.logger.info "[EstDoc] Remove orphaned index #{orphaned_id}"
          self.estraier_conn.out_doc docs[orphaned_id].attr('@id')
        end
        result[:records] = records.map{|record| record.estdoc = docs[record.id]; record}
        HINT_KEYS.each{|key| result[:info][key.downcase.to_sym] = rs.hint key}
      else
        raise
      end
      return result
    end

    def indexing!
      self.transaction do
        count = self.count
        ((count / 50).to_i + 1).times do |offset|
          self.find(:all, 'hoge', :limit => 50, :offset => 50 * offset).each do |record|
            record.update_est_index
          end
        end
        count
      end
    end
  end

  module InstanceMethods
    def to_estdoc
      doc = EstraierPure::Document::new
      doc.add_attr('@uri',         self.est_uri.to_s)
      doc.add_attr('@title',       self.est_title.to_s)
      doc.add_attr('record_id',    self.id.to_s)
      doc.add_attr('record_class', self.class.to_s)
      if respond_to? :est_attributes
        est_attributes.each do |name, value|
          doc.add_attr(name.to_s, value)
        end
      end
      if respond_to? :est_hidden_texts
        est_hidden_texts.to_a.each do |value|
          doc.add_hidden_text(value)
        end
      end
      est_texts.to_a.each do |value|
        doc.add_text(value)
      end
      doc
    end

    def to_xml_with_estdoc(*args)
      xml = to_xml_without_estdoc(*args).split("\n")
      options = args.extract_options!
      xml_foot = xml.pop
      xml << '  <estraier>'
      doc = estdoc || _estdoc
      if options[:with_pseudo_attributes]
        xml << '    <pseudo-attributes>'
        doc.attr_names.grep(/^#/).each do |name|
          xml << "      <#{name.sub('#', '')}>#{doc.attr(name)}</#{name.sub('#', '')}>"
        end
        xml << '    </pseudo-attributes>'
      end
      xml << '    <system-attributes>'
      doc.attr_names.grep(/^@/).each do |name|
        xml << "      <#{name.sub('@', '')}>#{doc.attr(name)}</#{name.sub('@', '')}>"
      end
      xml << '    </system-attributes>'
      xml << '    <attributes>'
      doc.attr_names.grep(/^[^@#]/).each do |name|
        next if name == 'record_id' or name == 'record_class'
        xml << "      <#{name}>#{doc.attr(name)}</#{name}>"
      end
      xml << '    </attributes>'
      xml << '  </estraier>'
      xml << xml_foot
      xml.join("\n")
    end

    def to_json_with_estdoc(*args)
      obj = ActiveSupport::JSON.decode(to_json_without_estdoc(*args))
      options = args.extract_options!
      doc = estdoc || _estdoc
      obj['estraier'] = {}
      if options[:with_pseudo_attributes]
        obj['estraier']['pseudo-attributes'] = {}
        doc.attr_names.grep(/^#/).each do |name|
          obj['estraier']['pseudo-attributes'][name.sub('#', '')] = doc.attr(name)
        end
      end
      obj['estraier']['system-attributes'] = {}
      doc.attr_names.grep(/^@/).each do |name|
        obj['estraier']['system-attributes'][name.sub('@', '')] = doc.attr(name)
      end
      obj['estraier']['attributes'] = {}
      doc.attr_names.grep(/^[^@#]/).each do |name|
        next if name == 'record_id' or name == 'record_class'
        obj['estraier']['attributes'][name] = doc.attr(name)
      end
      ActiveSupport::JSON.encode(obj)
    end

    def update_est_index
      return if self.skip_update_est_index
      raise  if new_record?
      begin
        remove_est_index
      rescue
      end
      add_est_index
    end

    def add_est_index
      raise  if new_record?
      return if respond_to?(:est_no_index) and est_no_index
      raise self.estraier_conn.status.to_s unless self.estraier_conn.put_doc(to_estdoc)
    end

    def remove_est_index
      raise if new_record?
      raise self.estraier_conn.status.to_s unless self.estraier_conn.out_doc(est_id)
    end

    def est_id
      raise if new_record?
      _estdoc.attr('@id')
    end

    private
    def _estdoc
      self.class.est_search('', :attributes => ["record_id NUMEQ #{self.id.to_s}", "record_class STREQ #{self.class.to_s}"])[:records][0].estdoc
    end
  end
end

ActiveRecord::Base.send :include, ActsAsEstraierDoc
