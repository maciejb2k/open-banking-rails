ActiveSupport.on_load(:active_record) do
  PaperTrail::Version.class_eval do
    def self.ransackable_attributes(_auth_object = nil)
      %w[created_at event id item_id item_type object object_changes whodunnit]
    end

    def self.ransackable_associations(_auth_object = nil)
      []
    end
  end
end
