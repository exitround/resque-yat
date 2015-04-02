# Generated by jeweler
# DO NOT EDIT THIS FILE DIRECTLY
# Instead, edit Jeweler::Tasks in Rakefile, and run 'rake gemspec'
# -*- encoding: utf-8 -*-
# stub: resque-yat 0.0.3 ruby lib

Gem::Specification.new do |s|
  s.name = "resque-yat"
  s.version = "0.0.3"

  s.required_rubygems_version = Gem::Requirement.new(">= 0") if s.respond_to? :required_rubygems_version=
  s.require_paths = ["lib"]
  s.authors = ["Val Savvateev", "Greg Dean"]
  s.date = "2015-04-02"
  s.description = "Resque jobs throttling gem"
  s.email = "dev@exitround.com"
  s.extra_rdoc_files = [
    "LICENSE.txt",
    "README.rdoc"
  ]
  s.files = [
    "Gemfile",
    "Gemfile.lock",
    "LICENSE.txt",
    "README.rdoc",
    "Rakefile",
    "VERSION",
    "lib/resque-yat.rb",
    "lib/resque-yat/job_extension.rb",
    "lib/resque-yat/rate_limiter.rb",
    "lib/resque-yat/resque_extension.rb",
    "lib/resque-yat/yat.rb",
    "resque-yat.gemspec",
    "spec/yat_spec.rb"
  ]
  s.homepage = "http://github.com/exitround/resque-yat"
  s.licenses = ["MIT"]
  s.rubygems_version = "2.4.5"
  s.summary = "Yet Another Thottler for Resque"

  if s.respond_to? :specification_version then
    s.specification_version = 4

    if Gem::Version.new(Gem::VERSION) >= Gem::Version.new('1.2.0') then
      s.add_runtime_dependency(%q<resque>, ["~> 1.25.2"])
      s.add_development_dependency(%q<rspec>, [">= 0"])
      s.add_development_dependency(%q<rdoc>, [">= 0"])
      s.add_development_dependency(%q<bundler>, [">= 0"])
      s.add_development_dependency(%q<jeweler>, [">= 0"])
    else
      s.add_dependency(%q<resque>, ["~> 1.25.2"])
      s.add_dependency(%q<rspec>, [">= 0"])
      s.add_dependency(%q<rdoc>, [">= 0"])
      s.add_dependency(%q<bundler>, [">= 0"])
      s.add_dependency(%q<jeweler>, [">= 0"])
    end
  else
    s.add_dependency(%q<resque>, ["~> 1.25.2"])
    s.add_dependency(%q<rspec>, [">= 0"])
    s.add_dependency(%q<rdoc>, [">= 0"])
    s.add_dependency(%q<bundler>, [">= 0"])
    s.add_dependency(%q<jeweler>, [">= 0"])
  end
end

