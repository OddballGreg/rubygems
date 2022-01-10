# frozen_string_literal: true

module Bundler
  class SourceMap
    attr_reader :sources, :dependencies

    def initialize(sources, dependencies)
      @sources = sources
      @dependencies = dependencies
    end

    def pinned_spec_names(skip = nil)
      direct_requirements.reject {|_, source| source == skip }.keys
    end

    def all_requirements
      requirements = direct_requirements.dup
      direct_dependency_parents = @dependencies.map{|dep| dep.to_spec.dependencies.map{|sub_dep| {sub_dep.name => dep.name} } }.compact.flatten.reduce(&:merge)

      unmet_deps = sources.non_default_explicit_sources.map do |source|
        (source.spec_names - pinned_spec_names).each do |indirect_dependency_name|
          previous_source = requirements[indirect_dependency_name]
          if previous_source.nil?
            explicit_parent = @dependencies.find{ |dependency| dependency.name == direct_dependency_parents[indirect_dependency_name] } 
            requirements[indirect_dependency_name] =  if explicit_parent && explicit_parent.preferred_spec_source
              sources.rubygems_sources.find{|source| source.name == "rubygems repository #{explicit_parent.preferred_spec_source}"}
            else
              requirements[direct_dependency_parents[indirect_dependency_name]]
            end
          else
            no_ambiguous_sources = Bundler.feature_flag.bundler_3_mode?

            msg = ["The gem '#{indirect_dependency_name}' was found in multiple relevant sources."]
            msg.concat [previous_source, source].map {|s| "  * #{s}" }.sort
            msg << "You #{no_ambiguous_sources ? :must : :should} add this gem to the source block for the source you wish it to be installed from."
            msg = msg.join("\n")

            raise SecurityError, msg if no_ambiguous_sources
            Bundler.ui.warn "Warning: #{msg}"
          end
        end

        source.unmet_deps
      end

      sources.default_source.add_dependency_names(unmet_deps.flatten - requirements.keys)

      requirements
    end

    def direct_requirements
      @direct_requirements ||= begin
        requirements = {}
        default = sources.default_source
        dependencies.each do |dep|
          dep_source = dep.source || default
          dep_source.add_dependency_names(dep.name)
          requirements[dep.name] = dep_source
        end
        requirements
      end
    end
  end
end
