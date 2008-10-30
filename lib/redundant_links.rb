module RedundantLinks
  def self.included(base)
    base.extend ClassMethods
    require 'redundant_link' # model class
    
    def method_missing(method_name, *args)
      check_scope_for_redundant_links(method_name, :send) || super
    end
    
    def respond_to?(method_name)
      check_scope_for_redundant_links(method_name, :respond_to?) || super
    end
    
  private
    def check_scope_for_redundant_links(method_name, action)
      if method_name.to_s =~ /\Aredundant\_linked\_\w+/ 
        association_name = method_name.to_s.gsub 'redundant_linked_', ''
        model = association_name.classify.constantize rescue nil
        model.send(action, "scope_for_redundant_linked_#{self.class.base_class.to_s.underscore}", self)
      end
    end
  end
  
  module ClassMethods
    
    # Call this method in your model to add the features of this plugin
    #
    # === Options
    #
    # The method expects a hash with the classes as keys and the association fields as values
    #
    #
    # === Example
    #
    # class Note << ActiveRecord::Base
    #   has_redundant_links Note => :object, 
    #                       Order => :contact, 
    #                       Contact => nil
    # end
    #  
    # == Created methods
    #  
    # * Instance method <tt>redundant_linked_notes</tt> for Order and Contact
    # * Class method <tt>rebuild_redundant_links</tt> for Note (useful for first time fill up of the join table)
    #
    # For creating and updating the join table there are some hooks installed
    def has_redundant_links(options)
      raise ArgumentError, "Parameter 'options' has to be a Hash" unless options.is_a?(Hash)
      raise ArgumentError, "Class #{self} has to be a key of parameter 'options', too!" unless options[self]

      options.each_pair do |k,v|
        # Make sure all values are arrays
        options[k] = [v] unless v.is_a?(Array) || v.nil?
        
        # Make sure all options values are nil OR arrays of symbols
        unless options[k].nil? || options[k].all? { |e| e.is_a?(Symbol) }
          raise ArgumentError, "All values of parameter 'options' have to be arrays of symbol (or nil)"
        end
      end
      
      cattr_accessor :redundant_links_options
      self.redundant_links_options = options
      
      options.keys.each do |klass|
        raise ArgumentError, "All keys of parameter 'options' have to be classes" unless klass.is_a?(Class)
        
        unless klass == self
          klass.class_eval <<-EOV
            has_many :redundant_links, :as => :to, :dependent => :delete_all

            # Update links, if master record was changed
            after_update :update_redundant_links_for_#{self.to_s.tableize}

            def update_redundant_links_for_#{self.to_s.tableize}
              first_record = redundant_linked_#{self.to_s.tableize}.first
            
              changed = false
              if targets = #{self}.redundant_links_options[#{klass}]
                targets.each do |target|              
                  if target_object = self.send(target)
                    if first_record
                      changed = true if not RedundantLink.exists?(:from_id => first_record.id, :from_type => first_record.class.base_class.to_s, :to_id => target_object.id, :to_type => target_object.class.base_class.to_s)
                    else
                      changed = true
                    end
                  else
                    if first_record
                      changed = true if RedundantLink.exists?(:from_id => first_record.id, :from_type => first_record.class.base_class.to_s)
                    end
                  end
              
                  break if changed
                end
              end
            
              if changed
                self.redundant_linked_#{self.to_s.tableize}.each do |record|
                  record.send :update_redundant_links
                end
              end
            end
          EOV
        end
        
        # In the detail class: Build a class method to get a scope, e.g. "scope_for_redundant_linked_customer(record)"
        self.class_eval <<-EOV
          def self.scope_for_redundant_linked_#{klass.base_class.to_s.underscore}(record)
            scoped :joins => "INNER JOIN redundant_links ON (redundant_links.to_id     = \#{record.id.is_a?(String) ? '"' + record.id + '"' : record.id }
                                                         AND redundant_links.to_type   = '\#{record.class.base_class}'
                                                         AND redundant_links.from_id   = #{self.to_s.tableize}.id
                                                         AND redundant_links.from_type = '#{self}')"
          end
        EOV
      end

      has_many :redundant_links, :as => :from, :dependent => :delete_all
      after_save :update_redundant_links
      
      send :include, RedundantLinks::InstanceMethods
      
      self.class_eval do
        def self.rebuild_redundant_links
          transaction do
            RedundantLink.delete_all :from_type => self.to_s
        
            find(:all).each do |record| 
              record.send :create_all_redundant_links
            end
          end
        end
      end
    end
  end
  
  module InstanceMethods
    
  private
    def update_redundant_links
      redundant_links.delete_all unless new_record?
      create_all_redundant_links
    end

    def create_all_redundant_links(base_object=self)
      @stored_redundant_links = [] if base_object == self

      self.class.redundant_links_options.keys.each do |klass|
        if base_object.is_a?(klass)
          if targets = self.class.redundant_links_options[klass]
            targets.each do |target|
              if target_object = base_object.send(target)
                unless @stored_redundant_links.include?(target_object)
                  self.redundant_links.create! :to => target_object
                  @stored_redundant_links << target_object
                end
          
                create_all_redundant_links(target_object)
              end
            end
          end
        end
      end
    end
  end
end