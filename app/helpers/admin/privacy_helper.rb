# frozen_string_literal: true

module Admin
  # All-or-nothing - no hover-to-reveal (would leak on screen-share). Class is
  # rendered server-side via cookie so there's no flash of unredacted content.
  #
  # Kinds: :blur (default) / :strong (heavy, for JSON+certs) / :redact (block,
  # for inline secrets) / :mask (bullets for fixed-format values).
  module PrivacyHelper
    PRIVACY_COOKIE = "privacy_mode"
    KINDS = %i[blur strong redact mask].freeze
    DEFAULT_KIND = :blur

    def privacy_mode?
      preference?(PRIVACY_COOKIE)
    end

    # Skips wrapping when value is blank - keeps "-" placeholders unredacted.
    def sensitive(value, kind: DEFAULT_KIND, tag: :span, **html_opts)
      return value if value.blank?

      classes = sensitive_class(kind: kind, extra: html_opts.delete(:class))
      content_tag(tag, value, **html_opts, class: classes)
    end

    def sensitive_block(kind: DEFAULT_KIND, tag: :div, **html_opts, &block)
      classes = sensitive_class(kind: kind, extra: html_opts.delete(:class))
      content_tag(tag, capture(&block), **html_opts, class: classes)
    end

    def sensitive_class(kind: DEFAULT_KIND, extra: nil)
      kind = DEFAULT_KIND unless KINDS.include?(kind)
      classes = [ "sensitive", "sensitive--#{kind}" ]
      classes << extra if extra.present?
      classes.join(" ")
    end

    # Normalize a `sensitive:` prop accepted by components - true / Symbol /
    # Hash{kind:, extra:}. Returns nil for false/nil.
    def sensitive_prop(value)
      case value
      when nil, false then nil
      when true       then sensitive_class
      when Symbol     then sensitive_class(kind: value)
      when Hash       then sensitive_class(**value.symbolize_keys.slice(:kind, :extra))
      end
    end
  end
end
