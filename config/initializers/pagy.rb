# frozen_string_literal: true

# Pagy initializer file
# See https://ddnexus.github.io/pagy/resources/initializer/

Pagy::OPTIONS[:limit] = 10           # Items per page
Pagy::OPTIONS[:max_limit] = 100      # Maximum items the client can request

Pagy::OPTIONS.freeze
