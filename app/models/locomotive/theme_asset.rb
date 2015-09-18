module Locomotive
  class ThemeAsset

    include Locomotive::Mongoid::Document

    ## extensions ##
    include Concerns::Shared::SiteScope
    include Concerns::Asset::Types
    include Concerns::Asset::Checksum

    ## fields ##
    field :local_path
    field :content_type,  type: Symbol
    field :width,         type: Integer
    field :height,        type: Integer
    field :size,          type: Integer
    field :folder,        default: nil

    mount_uploader :source, ThemeAssetUploader, mount_on: :source_filename, validate_integrity: true

    # indexes
    index site_id: 1, local_path: 1

    ## callbacks ##
    before_validation :check_for_folder_changes
    before_validation :store_plain_text
    before_validation :sanitize_folder
    before_validation :build_local_path

    ## validations ##
    validates_presence_of   :site
    validates_presence_of   :source, on: :create
    validates_presence_of   :plain_text_name, if: Proc.new { |a| a.performing_plain_text? }
    validates_uniqueness_of :local_path, scope: :site_id
    validate                :content_type_can_not_change

    ## named scopes ##

    ## accessors ##
    attr_accessor   :plain_text_name, :plain_text, :plain_text_type, :performing_plain_text

    ## methods ##

    def stylesheet_or_javascript?
      self.stylesheet? || self.javascript?
    end

    def local_path(short = false)
      if short && self.read_attribute(:local_path)
        # self.read_attribute(:local_path).gsub(/^#{self.content_type.to_s.pluralize}\//, '')
        self.read_attribute(:local_path).split('/')[1..-1].join('/')
      else
        self.read_attribute(:local_path)
      end
    end

    def plain_text_name
      if not @plain_text_name_changed
        @plain_text_name ||= self.safe_source_filename
      end
      @plain_text_name.gsub(/(\.[a-z0-9A-Z]+)$/, '') rescue nil
    end

    def plain_text_name=(name)
      @plain_text_name_changed = true
      @plain_text_name = name
    end

    def plain_text
      # only for ruby >= 1.9.x. Forget about ruby 1.8
      @plain_text ||= (self.source.read.force_encoding('UTF-8') rescue nil)
    end

    def plain_text_type
      @plain_text_type || (stylesheet_or_javascript? ? self.content_type : nil)
    end

    def performing_plain_text?
      Boolean.set(self.performing_plain_text) || false
    end

    def store_plain_text
      return if self.persisted? && !self.stylesheet_or_javascript?

      self.content_type ||= @plain_text_type if self.performing_plain_text?

      data = self.performing_plain_text? ? self.plain_text : self.source.read

      return if !self.stylesheet_or_javascript? || self.plain_text_name.blank? || data.blank?

      sanitized_source = self.escape_shortcut_urls(data)

      self.source = ::CarrierWave::SanitizedFile.new({
        tempfile: StringIO.new(sanitized_source),
        filename: "#{self.plain_text_name}.#{self.stylesheet? ? 'css' : 'js'}"
      })

      @plain_text = sanitized_source # no need to reset the plain_text instance variable to have the last version
    end

    def touch_site_attribute
      :template_version
    end

    def self.all_grouped_by_folder(site)
      assets = site.theme_assets.order_by(:slug.asc)
      assets.group_by { |a| a.folder.split('/').first.to_sym }
    end

    def self.checksums
      {}.tap do |hash|
        self.only(:local_path, :checksum).each do |asset|
          hash[asset.local_path] = asset.checksum
        end
      end
    end

    protected

    def safe_source_filename
      self.source_filename || self.source.send(:original_filename) rescue nil
    end

    def sanitize_folder
      self.folder = self.content_type.to_s.pluralize if self.folder.blank?

      # no accents, no spaces, no leading and ending trails
      self.folder = ActiveSupport::Inflector.transliterate(self.folder).gsub(/(\s)+/, '_').gsub(/^\//, '').gsub(/\/$/, '')

      # folder should begin by a root folder
      if (self.folder =~ /^(stylesheets|javascripts|images|media|fonts|pdfs|others)($|\/)+/).nil?
        self.folder = File.join(self.content_type.to_s.pluralize, self.folder)
      end
    end

    def build_local_path
      if filename = self.safe_source_filename
        self.local_path = File.join(self.folder, filename)
      else
        nil
      end
    end

    def escape_shortcut_urls(text)
      return if text.blank?

      text.gsub(/[("'](\/(stylesheets|javascripts|images|media|fonts|pdfs|others)\/(([^;.]+)\/)*([a-zA-Z_\-0-9]+)\.[a-z]{2,4})(\?[0-9]+)?[)"']/) do |path|

        sanitized_path = path.gsub(/[("')]/, '').gsub(/^\//, '').gsub(/\?[0-9]+$/, '')

        if asset = self.site.theme_assets.where(local_path: sanitized_path).first
          timestamp = self.updated_at.to_i
          "#{path.first}#{asset.source.url}?#{timestamp}#{path.last}"
        else
          path
        end
      end
    end

    def check_for_folder_changes
      # https://github.com/jnicklas/carrierwave/issues/330
      # https://github.com/jnicklas/carrierwave-mongoid/issues/23
      if self.persisted? && self.folder_changed? && !self.changed_attributes.key?('source_filename')
        # a simple way to rename a file
        old_asset         = self.class.where(_id: self._id).first # bypass memoization by mongoid
        file              = old_asset.source.file
        file.content_type = File.mime_type?(file.path) if file.content_type.nil?
        self.source       = file
        self.changed_attributes['source_filename'] = nil # delete the old file
      end
    end

    def content_type_can_not_change
      if self.persisted?
        # FIXME: content type used to be a String
        if self.content_type_was.to_sym != self.content_type
          self.errors.add(:source, :extname_changed)
        end
      end
    end

  end
end
