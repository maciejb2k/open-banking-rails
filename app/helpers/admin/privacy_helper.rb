# frozen_string_literal: true

module Admin
  # Privacy mode — hides sensitive data (amounts, IBANs, names, secrets, raw API
  # payloads) so the app can be safely demoed on screen-share / screenshots.
  #
  # Toggled from the topbar; persisted in a cookie so the html.privacy-mode
  # class is rendered server-side and there's no flash of unredacted content.
  #
  # ── Usage ──────────────────────────────────────────────────────────────────
  #   <%= sensitive account.iban %>                       # default :blur
  #   <%= sensitive amount, kind: :blur %>
  #   <%= sensitive secret, kind: :strong, reveal: false %>
  #   <% sensitive_block kind: :strong do %><%= big_thing %><% end %>
  #
  #   <span class="<%= sensitive_class %>">...</span>     # raw class on existing element
  #
  # Components like `definition_list` and `json_viewer` already accept a
  # `sensitive:` prop — pass `true` (default kind) or a symbol like `:strong`.
  #
  # ── Kinds ──────────────────────────────────────────────────────────────────
  #   :blur    — light blur, hover-to-reveal (default; good for short values)
  #   :strong  — heavy blur, NO hover-reveal (for JSON, certs, payloads)
  #   :redact  — solid block, no reveal (for inline secrets like keys)
  #   :mask    — replaces text with bullets (•••) (for fixed-format values)
  module PrivacyHelper
    PRIVACY_COOKIE = "privacy_mode"
    KINDS = %i[blur strong redact mask].freeze
    DEFAULT_KIND = :blur

    def privacy_mode?
      preference?(PRIVACY_COOKIE)
    end

    # Wrap a value in a sensitive span (or other tag).
    # Skips wrapping when value is blank — keeps "—" placeholders unredacted.
    def sensitive(value, kind: DEFAULT_KIND, reveal: true, tag: :span, **html_opts)
      return value if value.blank?

      classes = sensitive_class(kind: kind, reveal: reveal, extra: html_opts.delete(:class))
      content_tag(tag, value, **html_opts, class: classes)
    end

    # Block form — wraps arbitrary content (good for whole cards / JSON viewers).
    def sensitive_block(kind: DEFAULT_KIND, reveal: true, tag: :div, **html_opts, &block)
      classes = sensitive_class(kind: kind, reveal: reveal, extra: html_opts.delete(:class))
      content_tag(tag, capture(&block), **html_opts, class: classes)
    end

    # Just the class string — for use inline on existing elements:
    #   <pre class="<%= sensitive_class kind: :strong %>">...</pre>
    def sensitive_class(kind: DEFAULT_KIND, reveal: true, extra: nil)
      kind = DEFAULT_KIND unless KINDS.include?(kind)
      classes = [ "sensitive", "sensitive--#{kind}" ]
      classes << "sensitive--no-reveal" unless reveal
      classes << extra if extra.present?
      classes.join(" ")
    end

    # Normalize a `sensitive:` prop accepted by components.
    # Returns nil if disabled, or a class string ready to drop on the element.
    #   sensitive_prop(false)        # => nil
    #   sensitive_prop(true)         # => "sensitive sensitive--blur"
    #   sensitive_prop(:strong)      # => "sensitive sensitive--strong"
    #   sensitive_prop({ kind: :redact, reveal: false })
    def sensitive_prop(value)
      case value
      when nil, false then nil
      when true       then sensitive_class
      when Symbol     then sensitive_class(kind: value)
      when Hash       then sensitive_class(**value.symbolize_keys.slice(:kind, :reveal, :extra))
      end
    end
  end
end
