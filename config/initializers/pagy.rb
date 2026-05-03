# frozen_string_literal: true

# See https://ddnexus.github.io/pagy/resources/initializer/

Pagy::OPTIONS[:limit] = 10
Pagy::OPTIONS[:max_limit] = 100

Pagy::OPTIONS.freeze
