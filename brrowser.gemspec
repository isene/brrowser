Gem::Specification.new do |s|
  s.name          = 'brrowser'
  s.version       = '0.1.0'
  s.licenses      = ['Unlicense']
  s.summary       = "brrowser - A terminal web browser with vim-style keybindings"
  s.description   = "A terminal web browser combining w3m-style rendering with qutebrowser-style vim keybindings. Features hint mode for link following, tabs, search, bookmarks, and more. Built on rcurses."
  s.authors       = ["Geir Isene"]
  s.email         = 'g@isene.com'
  s.homepage      = 'https://isene.com/'
  s.metadata      = { "source_code_uri" => "https://github.com/isene/brrowser" }
  s.files         = Dir['{bin,lib}/**/*', 'README.md', 'LICENSE']
  s.executables   = ['brrowser']
  s.require_paths = ['lib']
  s.required_ruby_version = '>= 3.0'
  s.add_runtime_dependency 'rcurses', '~> 6.0'
  s.add_runtime_dependency 'nokogiri', '~> 1.0'
  s.add_runtime_dependency 'termpix', '~> 0.3'
end
