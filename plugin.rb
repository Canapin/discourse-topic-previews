# name: discourse-topic-list-previews
# about: Allows you to add topic previews and other topic features to topic lists
# version: 0.4
# authors: Angus McLeod
# url: https://github.com/angusmcleod/discourse-topic-previews

register_asset 'stylesheets/previews_common.scss'
register_asset 'stylesheets/previews_mobile.scss'
register_asset 'javascripts/discourse/lib/masonry/masonry.js'
register_asset 'javascripts/discourse/lib/imagesloaded/imagesloaded.js'

register_svg_icon "bookmark" if respond_to?(:register_svg_icon)
register_svg_icon "heart" if respond_to?(:register_svg_icon)

enabled_site_setting :topic_list_previews_enabled

after_initialize do

  Jobs.module_eval do

    class PullHotlinkedImages < Jobs::Base
      sidekiq_options queue: 'critical'

      def initialize
        @max_size = SiteSetting.max_image_size_kb.kilobytes
      end

      def download(src)
        downloaded = nil

        begin
          retries ||= 3

          downloaded = FileHelper.download(
            src,
            max_file_size: @max_size,
            retain_on_max_file_size_exceeded: true,
            tmp_file_name: "discourse-hotlinked",
            follow_redirect: true
          )
        rescue
          if (retries -= 1) > 0 && !Rails.env.test?
            sleep 1
            retry
          end
        end

        downloaded
      end

      def execute(args)
        return unless SiteSetting.download_remote_images_to_local?

        post_id = args[:post_id]
        raise Discourse::InvalidParameters.new(:post_id) unless post_id.present?

        post = Post.find_by(id: post_id)
        return unless post.present?

        raw = post.raw.dup
        start_raw = raw.dup

        downloaded_urls = {}

        large_images = JSON.parse(post.custom_fields[Post::LARGE_IMAGES].presence || "[]")
        broken_images = JSON.parse(post.custom_fields[Post::BROKEN_IMAGES].presence || "[]")
        downloaded_images = JSON.parse(post.custom_fields[Post::DOWNLOADED_IMAGES].presence || "{}")

        has_new_large_image  = false
        has_new_broken_image = false
        has_downloaded_image = false

        extract_images_from(post.cooked).each do |image|
          src = original_src = image['src']
          src = "#{SiteSetting.force_https ? "https" : "http"}:#{src}" if src.start_with?("//")

          if is_valid_image_url(src)
            begin
              # have we already downloaded that file?
              schemeless_src = remove_scheme(original_src)

              unless downloaded_images.include?(schemeless_src) || large_images.include?(schemeless_src) || broken_images.include?(schemeless_src)
                if hotlinked = download(src)
                  if File.size(hotlinked.path) <= @max_size
                    filename = File.basename(URI.parse(src).path)
                    filename << File.extname(hotlinked.path) unless filename["."]
                    upload = UploadCreator.new(hotlinked, filename, origin: src).create_for(post.user_id)
                    if upload.persisted?
                      downloaded_urls[src] = upload.url
                      downloaded_images[remove_scheme(src)] = upload.id
                      has_downloaded_image = true
                    else
                      log(:info, "Failed to pull hotlinked image for post: #{post_id}: #{src} - #{upload.errors.full_messages.join("\n")}")
                    end
                  else
                    large_images << remove_scheme(original_src)
                    has_new_large_image = true
                  end
                else
                  broken_images << remove_scheme(original_src)
                  has_new_broken_image = true
                end
              end
              # have we successfully downloaded that file?
              if downloaded_urls[src].present?
                url = downloaded_urls[src]
                escaped_src = Regexp.escape(original_src)
                # there are 6 ways to insert an image in a post
                # HTML tag - <img src="http://...">
                raw.gsub!(/src=["']#{escaped_src}["']/i, "src='#{url}'")
                # BBCode tag - [img]http://...[/img]
                raw.gsub!(/\[img\]#{escaped_src}\[\/img\]/i, "[img]#{url}[/img]")
                # Markdown linked image - [![alt](http://...)](http://...)
                raw.gsub!(/\[!\[([^\]]*)\]\(#{escaped_src}\)\]/) { "[<img src='#{url}' alt='#{$1}'>]" }
                # Markdown inline - ![alt](http://...)
                raw.gsub!(/!\[([^\]]*)\]\(#{escaped_src}\)/) { "![#{$1}](#{url})" }
                # Markdown inline - ![](http://... "image title")
                raw.gsub!(/!\[\]\(#{escaped_src} "([^\]]*)"\)/) { "![](#{url})" }
                # Markdown inline - ![alt](http://... "image title")
                raw.gsub!(/!\[([^\]]*)\]\(#{escaped_src} "([^\]]*)"\)/) { "![](#{url})" }
                # Markdown reference - [x]: http://
                raw.gsub!(/\[([^\]]+)\]:\s?#{escaped_src}/) { "[#{$1}]: #{url}" }
                # Direct link
                raw.gsub!(/^#{escaped_src}(\s?)$/) { "<img src='#{url}'>#{$1}" }
              end
            rescue => e
              log(:error, "Failed to pull hotlinked image (#{src}) post: #{post_id}\n" + e.message + "\n" + e.backtrace.join("\n"))
            end
          end
        end

        large_images.uniq!
        broken_images.uniq!

        post.custom_fields[Post::LARGE_IMAGES]      = large_images.to_json      if large_images.present?
        post.custom_fields[Post::BROKEN_IMAGES]     = broken_images.to_json     if broken_images.present?
        post.custom_fields[Post::DOWNLOADED_IMAGES] = downloaded_images.to_json if downloaded_images.present?
        # only save custom fields if there are any
        post.save_custom_fields if large_images.present? || broken_images.present? || downloaded_images.present?

        post.reload

        if start_raw == post.raw && raw != post.raw
          changes = { raw: raw, edit_reason: I18n.t("upload.edit_reason") }
          post.revise(Discourse.system_user, changes, bypass_bump: true)
        elsif has_downloaded_image || has_new_large_image || has_new_broken_image
          post.trigger_post_process(bypass_bump: true)
        end
      end

      def extract_images_from(html)
        doc = Nokogiri::HTML::fragment(html)
        doc.css("img[src]") - doc.css("img.avatar")
      end

      def is_valid_image_url(src)
        # make sure we actually have a url
        return false unless src.present?
        # we don't want to pull uploaded images
        return false if Discourse.store.has_been_uploaded?(src)
        # we don't want to pull relative images
        return false if src =~ /\A\/[^\/]/i

        # parse the src
        begin
          uri = URI.parse(src)
        rescue URI::Error
          return false
        end

        hostname = uri.hostname
        return false unless hostname

        # we don't want to pull images hosted on the CDN (if we use one)
        return false if Discourse.asset_host.present? && URI.parse(Discourse.asset_host).hostname == hostname
        return false if SiteSetting.Upload.s3_cdn_url.present? && URI.parse(SiteSetting.Upload.s3_cdn_url).hostname == hostname
        # we don't want to pull images hosted on the main domain
        return false if URI.parse(Discourse.base_url_no_prefix).hostname == hostname
        # check the domains blacklist
        SiteSetting.should_download_images?(src)
      end

      def log(log_level, message)
        Rails.logger.public_send(
          log_level,
          "#{RailsMultisite::ConnectionManagement.current_db}: #{message}"
        )
      end

      private

      def remove_scheme(src)
        src.sub(/^https?:/i, "")
      end
    end
  end

  Topic.register_custom_field_type('thumbnails', :json)
  Category.register_custom_field_type('thumbnail_width', :integer)
  Category.register_custom_field_type('thumbnail_height', :integer)
  Category.register_custom_field_type('topic_list_featured_images', :boolean)
  SiteSetting.create_thumbnails = true

  @nil_thumbs = TopicCustomField.where(name: 'thumbnails', value: nil)
  if @nil_thumbs.length
    @nil_thumbs.each do |thumb|
      hash = { normal: '', retina: '' }
      thumb.value = ::JSON.generate(hash)
      thumb.save!
    end
  end

  module ::TopicPreviews
    class Engine < ::Rails::Engine
      engine_name "topic_previews"
      isolate_namespace TopicPreviews
    end
  end

  load File.expand_path('../lib/topic_list_previews_helper.rb', __FILE__)
  load File.expand_path('../lib/guardian_edits.rb', __FILE__)
  load File.expand_path('../lib/featured_topics.rb', __FILE__)
  load File.expand_path('../lib/topic_list_edits.rb', __FILE__)
  load File.expand_path('../lib/cooked_post_processor_edits.rb', __FILE__)
  load File.expand_path('../serializers/topic_list_item_edits.rb', __FILE__)

  TopicList.preloaded_custom_fields << "accepted_answer_post_id" if TopicList.respond_to? :preloaded_custom_fields
  TopicList.preloaded_custom_fields << "thumbnails" if TopicList.respond_to? :preloaded_custom_fields

  DiscourseEvent.on(:accepted_solution) do |post|
    if post.image_url && SiteSetting.topic_list_previews_enabled
      ListHelper.create_topic_thumbnails(post, post.image_url)
    end
  end

  add_to_serializer(:basic_category, :topic_list_tiles) { object.custom_fields["topic_list_tiles"] }
  add_to_serializer(:basic_category, :topic_list_excerpt) { object.custom_fields["topic_list_excerpt"] }
  add_to_serializer(:basic_category, :topic_list_thumbnail) { object.custom_fields["topic_list_thumbnail"] }
  add_to_serializer(:basic_category, :topic_list_action) { object.custom_fields["topic_list_action"] }
  add_to_serializer(:basic_category, :topic_list_tiles_transition_time) { object.custom_fields["topic_list_tiles_transition_time"] }
  add_to_serializer(:basic_category, :topic_list_category_column) { object.custom_fields["topic_list_category_column"] }
  add_to_serializer(:basic_category, :topic_list_default_thumbnail) { object.custom_fields["topic_list_default_thumbnail"] }
  add_to_serializer(:basic_category, :topic_list_thumbnail_width) { object.custom_fields['topic_list_thumbnail_width'] }
  add_to_serializer(:basic_category, :topic_list_thumbnail_height) { object.custom_fields['topic_list_thumbnail_height'] }
  add_to_serializer(:basic_category, :topic_list_featured_images) { object.custom_fields['topic_list_featured_images'] }

  DiscourseEvent.trigger(:topic_previews_ready)
end
