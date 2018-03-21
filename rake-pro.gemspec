
lib = File.expand_path("../lib", __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require "rake/pro/version"

Gem::Specification.new do |spec|
  spec.name          = "rake-pro"
  spec.version       = Rake::Pro::VERSION
  spec.authors       = ["Dean Hallman"]
  spec.email         = ["rdhallman@gmail.com"]

  spec.summary       = %q{Enterprise extensions for Rake.}
  spec.description   = %q{Adds support for key/value store with template expansion, ssh tunneling, local and remote shell improvements etc.}
  spec.homepage      = "http://www.github.com/"
  spec.license       = "MIT"

  #spec.files         = `git ls-files -z`.split("\x0").reject do |f|
    #f.match(%r{^(test|spec|features)/})
  #end
  spec.files         = Dir['lib/**/*.rb']

  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_development_dependency "bundler", "~> 1.16"
  spec.add_development_dependency "rake", "~> 10.0"
  spec.add_development_dependency "rspec", "~> 3.0"


  spec.add_dependency "rake"
  spec.add_dependency "open4", "~> 1.3"
  spec.add_dependency "openssl", "~> 2.1"
  spec.add_dependency "net-ssh-gateway", "~> 2.0"
end
