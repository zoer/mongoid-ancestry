module Mongoid
  module Ancestry
    module InstanceMethods
      def save!(opts = {})
        opts.merge!(:safe => true)
        retries = 3
        begin
          super(opts)
        rescue Mongo::OperationFailure => e
          (retries -= 1) > 0 && e.to_s =~ %r{duplicate key error.+\$#{self.base_class.uid_field}} ? retry : raise(e)
        end
      end
      alias_method :save, :save!

      def set_uid
        previous = self.class.desc(:"#{self.base_class.uid_field}").first
        uniq_id = previous ? previous.read_attribute(:"#{uid_field}").to_i + 1 : 1
        send :"#{uid_field}=", uniq_id
      end

      # Validate that the ancestors don't include itself
      def ancestry_exclude_self
        if ancestor_ids.include? read_attribute(self.base_class.uid_field)
          errors.add(:base, "#{self.class.name.humanize} cannot be a descendant of itself.")
        end
      end

      # Update descendants with new ancestry
      def update_descendants_with_new_ancestry
        # Skip this if callbacks are disabled
        unless ancestry_callbacks_disabled?
          # If node is valid, not a new record and ancestry was updated ...
          if changed.include?(self.base_class.ancestry_field.to_s) && !new_record? && valid?
            # ... for each descendant ...
            descendants.each do |descendant|
              # ... replace old ancestry with new ancestry
              descendant.without_ancestry_callbacks do
                for_replace = \
                  if read_attribute(self.class.ancestry_field).blank?
                    read_attribute(self.base_class.uid_field).to_s
                  else
                    "#{read_attribute self.class.ancestry_field }/#{uid}"
                  end
                new_ancestry = descendant.read_attribute(descendant.class.ancestry_field).gsub(/^#{self.child_ancestry}/, for_replace)
                descendant.update_attribute(self.base_class.ancestry_field, new_ancestry)
              end
            end
          end
        end
      end

      # Apply orphan strategy
      def apply_orphan_strategy
        # Skip this if callbacks are disabled
        unless ancestry_callbacks_disabled?
          # If this isn't a new record ...
          unless new_record?
            # ... make al children root if orphan strategy is rootify
            if self.base_class.orphan_strategy == :rootify
              descendants.each do |descendant|
                descendant.without_ancestry_callbacks do
                  val = \
                    unless descendant.ancestry == child_ancestry
                      descendant.read_attribute(descendant.class.ancestry_field).gsub(/^#{child_ancestry}\//, '')
                    end
                  descendant.update_attribute descendant.class.ancestry_field, val
                end
              end
              # ... destroy all descendants if orphan strategy is destroy
            elsif self.base_class.orphan_strategy == :destroy
              descendants.all.each do |descendant|
                descendant.without_ancestry_callbacks { descendant.destroy }
              end
              # ... throw an exception if it has children and orphan strategy is restrict
            elsif self.base_class.orphan_strategy == :restrict
              raise Error.new('Cannot delete record because it has descendants.') unless is_childless?
            end
          end
        end
      end

      # The ancestry value for this record's children
      def child_ancestry
        # New records cannot have children
        raise Error.new('No child ancestry for new record. Save record before performing tree operations.') if new_record?

        if self.send("#{self.base_class.ancestry_field}_was").blank?
          read_attribute(self.base_class.uid_field).to_s
        else
          "#{self.send "#{self.base_class.ancestry_field}_was"}/#{read_attribute(self.base_class.uid_field)}"
        end
      end

      # Ancestors
      def ancestor_ids
        read_attribute(self.base_class.ancestry_field).to_s.split('/').map{ |uid| uid.to_i }
      end

      def ancestor_conditions
        {self.base_class.uid_field.in => ancestor_ids}
      end

      def ancestors depth_options = {}
        self.base_class.scope_depth(depth_options, depth).where(ancestor_conditions)
      end

      def path_ids
        ancestor_ids + [read_attribute(self.base_class.uid_field)]
      end

      def path_conditions
        {self.base_class.uid_field.in => path_ids}
      end

      def path depth_options = {}
        self.base_class.scope_depth(depth_options, depth).where(path_conditions)
      end

      def depth
        ancestor_ids.size
      end

      def cache_depth
        write_attribute self.base_class.depth_cache_field, depth
      end

      # Parent
      def parent= parent
        write_attribute(self.base_class.ancestry_field, parent.blank? ? nil : parent.child_ancestry)
      end

      def parent_id= parent_id
        self.parent = parent_id.blank? ? nil : self.base_class.find_by_uid!(parent_id)
      end

      def parent_id
        ancestor_ids.empty? ? nil : ancestor_ids.last
      end

      def parent
        parent_id.blank? ? nil : self.base_class.find_by_uid!(parent_id)
      end

      # Root
      def root_id
        ancestor_ids.empty? ? read_attribute(self.base_class.uid_field) : ancestor_ids.first
      end

      def root
        (root_id == read_attribute(self.base_class.uid_field)) ? self : self.base_class.find_by_uid!(root_id)
      end

      def is_root?
        read_attribute(self.base_class.ancestry_field).blank?
      end

      # Children
      def child_conditions
        {self.base_class.ancestry_field => child_ancestry}
      end

      def children
        self.base_class.where(child_conditions)
      end

      def child_ids
        children.only(self.base_class.uid_field).all.map(&self.base_class.uid_field)
      end

      def has_children?
        self.children.present?
      end

      def is_childless?
        !has_children?
      end

      # Siblings
      def sibling_conditions
        {self.base_class.ancestry_field => read_attribute(self.base_class.ancestry_field)}
      end

      def siblings
        self.base_class.where sibling_conditions
      end

      def sibling_ids
        siblings.only(self.base_class.uid_field).all.collect(&self.base_class.uid_field)
      end

      def has_siblings?
        self.siblings.count > 1
      end

      def is_only_child?
        !has_siblings?
      end

      # Descendants
      def descendant_conditions
        #["#{self.base_class.ancestry_field} like ? or #{self.base_class.ancestry_column} = ?", "#{child_ancestry}/%", child_ancestry]
        [
          { self.base_class.ancestry_field => /^#{child_ancestry}\// },
          { self.base_class.ancestry_field => child_ancestry }
        ]
      end

      def descendants depth_options = {}
        self.base_class.scope_depth(depth_options, depth).any_of(descendant_conditions)
      end

      def descendant_ids depth_options = {}
        descendants(depth_options).only(self.base_class.uid_field).collect(&self.base_class.uid_field)
      end

      # Subtree
      def subtree_conditions
        #["#{self.base_class.primary_key} = ? or #{self.base_class.ancestry_column} like ? or #{self.base_class.ancestry_column} = ?", self.id, "#{child_ancestry}/%", child_ancestry]
          [
            { self.base_class.uid_field => read_attribute(self.base_class.uid_field) },
            { self.base_class.ancestry_field => /^#{child_ancestry}\// },
            { self.base_class.ancestry_field => child_ancestry }
          ]
      end

      def subtree depth_options = {}
        self.base_class.scope_depth(depth_options, depth).any_of(subtree_conditions)
      end

      def subtree_ids depth_options = {}
        subtree(depth_options).select(self.base_class.uid_field).all.collect(&self.base_class.uid_field)
      end

      # Callback disabling
      def without_ancestry_callbacks
        @disable_ancestry_callbacks = true
        yield
        @disable_ancestry_callbacks = false
      end

      def ancestry_callbacks_disabled?
        !!@disable_ancestry_callbacks
      end
    end
  end
end
