# frozen_string_literal: true

module SidekiqHelpers
  def with_inline_sidekiq
    previous = Sidekiq::Testing.__test_mode
    Sidekiq::Testing.inline!
    yield
  ensure
    case previous
    when :fake   then Sidekiq::Testing.fake!
    when :inline then Sidekiq::Testing.inline!
    when :disable then Sidekiq::Testing.disable!
    end
  end

  def drain_all_jobs
    Sidekiq::Worker.drain_all
  end

  def clear_jobs!
    Sidekiq::Worker.clear_all
  end
end
