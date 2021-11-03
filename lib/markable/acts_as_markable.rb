module Markable
  module ActsAsMarkable
    extend ActiveSupport::Concern

    module ClassMethods
      def markable_as(*args)
        options = args.extract_options!
        marks   = args.flatten
        by      = options[:by]

        Markable.set_models

        class_eval do
          class << self
            attr_accessor :__markable_marks
          end
        end

        marks = Array.wrap(marks).map!(&:to_sym)

        markers = by.present? ? Array.wrap(by) : :all

        self.__markable_marks ||= {}
        marks.each do |mark|
          self.__markable_marks[mark] = {
            :allowed_markers => markers
          }
        end

        class_eval do
          has_many :markable_marks,
                   :class_name => 'Markable::Mark',
                   :as => :markable,
                   :dependent => :delete_all
          include Markable::ActsAsMarkable::MarkableInstanceMethods

          def self.marked_as(mark, options = {})
            by = options[:by]
            if by.present?
              result = self.joins(:markable_marks).where({
                :marks => {
                  :mark => mark.to_s,
                  :marker_id => by.id,
                  :marker_type => by.class.name
                }
              })
              markable = self
              result.class_eval do
                define_method :<< do |object|
                  by.set_mark(mark, object)
                  self
                end
                define_method :delete do |markable|
                  by.remove_mark(mark, markable)
                  self
                end
              end
            else
              result = self.joins(:markable_marks).where(:marks => { :mark => mark.to_s }).group("#{self.table_name}.id")
            end
            result
          end
        end

        self.__markable_marks.each do |mark, o|
          class_eval %(
            def self.marked_as_#{mark}(options = {})
              self.marked_as(:#{mark}, options)
            end

            def marked_as_#{mark}?(options = {})
              self.marked_as?(:#{mark}, options)
            end
          )
        end

        Markable.add_markable(self)
      end
    end

    module MarkableInstanceMethods

      def method_missing(method_sym, *args)
        Markable.models.each do |model_name|
          if method_sym.to_s =~ Regexp.new("^#{model_name.downcase.pluralize}_have_marked_as(_[\\w_]+)?$")
            model_name.constantize # ping model

            if self.methods.include?(method_sym) # method has appear
              return self.method(method_sym).call(*args) # call this method
            end
          end
        end
        super
      rescue
        super
      end

      def mark_as(mark, markers)
        Array.wrap(markers).each do |marker|
          Markable.can_mark_or_raise?(marker, self, mark)
          params = {
            :markable_id => self.id,
            :markable_type => self.class.name,
            :marker_id => marker.id,
            :marker_type => marker.class.name,
            :mark => mark.to_s
          }
          Markable::Mark.create(params) unless Markable::Mark.exists?(params)
        end
      end

      def marked_as?(mark, options = {})
        by = options[:by]
        params = {
          :markable_id => self.id,
          :markable_type => self.class.name,
          :mark => mark.to_s
        }
        if by.present?
          Markable.can_mark_or_raise?(by, self, mark)
          params[:marker_id] = by.id
          params[:marker_type] = by.class.name
        end
        Markable::Mark.exists?(params)
      end

      def unmark(mark, options = {})
        by = options[:by]
        if by.present?
          Markable.can_mark_or_raise?(by, self, mark)
          Array.wrap(by).each do |marker|
            Markable::Mark.where(({
              :markable_id => self.id,
              :markable_type => self.class.name,
              :marker_id => marker.id,
              :marker_type => marker.class.name,
              :mark => mark.to_s
            })).delete_all
          end
        else
          Markable::Mark.where({
            :markable_id => self.id,
            :markable_type => self.class.name,
            :mark => mark.to_s
           }).delete_all
        end
      end

      def have_marked_as_by(mark, target)
        result = target.joins(:marker_marks).where({
          :marks => {
            :mark => mark.to_s,
            :markable_id => self.id,
            :markable_type => self.class.name
          }
        })
        markable = self
        result.class_eval do
          define_method :<< do |markers|
            Array.wrap(markers).each do |marker|
              marker.set_mark(mark, markable)
            end
            self
          end
          define_method :delete do |markers|
            Markable.can_mark_or_raise?(markers, markable, mark)
            Array.wrap(markers).each do |marker|
              marker.remove_mark(mark, markable)
            end
            self
          end
        end
        result
      end
    end
  end
end

ActiveRecord::Base.send(:include, Markable::ActsAsMarkable)
