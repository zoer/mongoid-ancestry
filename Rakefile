require 'rubygems'

require 'rake'

require 'jeweler'
Jeweler::Tasks.new do |gem|
  # gem is a Gem::Specification... see http://docs.rubygems.org/read/chapter/20 for more options
  gem.name = "mongoid-ancestry"
  gem.homepage = "http://github.com/skyeagle/mongoid-ancestry"
  gem.license = "MIT"
  gem.summary = %Q{'Ancestry allows the records of a Mongoid model to be organised in a tree structure, using a single, intuitively formatted database field. It exposes all the standard tree structure relations (ancestors, parent, root, children, siblings, descendants) and all of them can be fetched in a single query. Additional features are named_scopes, integrity checking, integrity restoration, arrangement of (sub)tree into hashes and different strategies for dealing with orphaned records.'}
  gem.description = %Q{Organise Mongoid model into a tree structure}
  gem.email = "eagle.anton@gmail.com"
  gem.authors = ["Stefan Kroes", "Anton Orel"]
  gem.add_runtime_dependency('mongoid', '~> 2.0')
  gem.add_runtime_dependency('bson_ext', '~> 1.3')
  gem.add_development_dependency 'rspec', '~> 2.5'
  gem.add_development_dependency 'bundler', '~> 1.0'
  gem.add_development_dependency 'guard-rspec', '~> 0.2'
  gem.add_development_dependency 'libnotify', '~> 0.3'
  gem.add_development_dependency 'rb-inotify', '~> 0.8'
  gem.add_development_dependency 'fuubar', '~> 0.0.4'
end
Jeweler::RubygemsDotOrgTasks.new

require 'rspec/core'
require 'rspec/core/rake_task'
RSpec::Core::RakeTask.new(:spec) do |spec|
  spec.pattern = FileList['spec/**/*_spec.rb']
end

task :default => :spec

require 'rake/rdoctask'
Rake::RDocTask.new do |rdoc|
  version = File.exist?('VERSION') ? File.read('VERSION') : ""

  rdoc.rdoc_dir = 'rdoc'
  rdoc.title = "mongoid-ancestry #{version}"
  rdoc.rdoc_files.include('README*')
  rdoc.rdoc_files.include('lib/**/*.rb')
end
