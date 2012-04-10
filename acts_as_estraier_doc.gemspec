# -*- encoding: utf-8 -*-
require File.expand_path('../lib/acts_as_estraier_doc/version', __FILE__)

Gem::Specification.new do |gem|
  gem.authors       = ["Takatoshi MORIYAMA"]
  gem.email         = ["hawk@at-exit.com"]
  gem.description   = %q{Acts as EstraierDoc}
  gem.summary       = %q{Acts as EstraierDoc}
  gem.homepage      = ""

  gem.files         = `git ls-files`.split($\)
  gem.executables   = gem.files.grep(%r{^bin/}).map{ |f| File.basename(f) }
  gem.test_files    = gem.files.grep(%r{^(test|spec|features)/})
  gem.name          = "acts_as_estraier_doc"
  gem.require_paths = ['lib', 'vendor']
  gem.version       = ActsAsEstraierDoc::VERSION

  gem.add_runtime_dependency 'activerecord', '~> 2.0'
end
