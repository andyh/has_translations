module HasTranslations
  module ModelAdditions
    extend ActiveSupport::Concern

    module ClassMethods
      def translated(locale)
        where(["#{self.has_translations_options[:translation_class].table_name}.locale = ?", locale.to_s]).joins(:translations)
      end

      def has_translations(*attrs)
        new_options = attrs.extract_options!
        options = {
          :fallback => false,
          :reader => true,
          :writer => false,
          :nil => '',
          :autosave => new_options[:writer],
          :translation_class => nil,
          :approval => true
        }.merge(new_options)

        translation_class_name =  options[:translation_class].try(:name) || "#{self.model_name}Translation"
        options[:translation_class] ||= translation_class_name.constantize

        options.assert_valid_keys([:fallback, :reader, :writer, :nil, :autosave, :translation_class, :approval])

        belongs_to = self.model_name.demodulize.underscore.to_sym

        class_attribute :has_translations_options
        self.has_translations_options = options

        # associations, validations and scope definitions
        has_many :translations, :class_name => translation_class_name, :dependent => :destroy, :autosave => options[:autosave]
        options[:translation_class].belongs_to belongs_to
        options[:translation_class].validates_presence_of :locale
        options[:translation_class].validates_presence_of :status
        options[:translation_class].validates_uniqueness_of :locale, :scope => [:"#{belongs_to}_id", :status]

        # Optionals delegated readers
        if options[:reader]
          attrs.each do |name|
            send :define_method, name do |*args|
              locale = args.first || I18n.locale
              status = options[:approval] ? "approved" : false
              translation = self.translation(locale, status)
              translation.try(name) || has_translations_options[:nil]
            end
          end
        end

        # Optionals delegated writers
        if options[:writer]
          attrs.each do |name|
            send :define_method, "#{name}_before_type_cast" do
              status = options[:approval] ? "approved" : false
              translation = self.translation(I18n.default_locale, status, false)
              translation.try(name)
            end

            send :define_method, "#{name}=" do |value|
              status = options[:approval] ? "approved" : false
              translation = find_or_build_translation(I18n.default_locale, status)
              translation.send(:"#{name}=", value)
            end
          end
        end

      end
    end

    def find_or_create_translation(locale, status)
      locale = locale.to_s
      (find_translation(locale, status) || self.has_translations_options[:translation_class].new).tap do |t|
        t.locale = locale
        t.send(:"#{self.class.model_name.demodulize.underscore.to_sym}_id=", self.id)
      end
    end

    def find_or_build_translation(locale, status)
      locale = locale.to_s
      status = status.to_s
      (find_translation(locale, status) || self.translations.build).tap do |t|
        t.locale = locale
        t.status = status
      end
    end

    def translation(locale, status = false, fallback=has_translations_options[:fallback])
      locale = locale.to_s
      find_translation(locale,status) || (fallback && !translations.blank? ? translations.detect { |t| t.locale == I18n.default_locale.to_s && t.status == "approved" } || translations.first : nil)
    end

    def all_translations(status = false)
      t = I18n.available_locales.map do |locale|
        [locale, find_or_create_translation(locale, status)]
      end
      ActiveSupport::OrderedHash[t]
    end

    def has_translation?(locale, status = false)
      find_translation(locale, status).present?
    end

    def find_translation(locale,status)
      locale = locale.to_s
      if status
        translations.detect { |t| t.locale == locale && t.status == status }
      else
        translations.detect { |t| t.locale == locale }
      end
    end
  end
end
