WEBPACKER_APP_TEMPLATE_PATH = File.expand_path('../install/template.rb', __dir__)
REGEX_MAP = /\A.*\.map\z/

namespace :webpacker do
  desc "Compile javascript packs using webpack for production with digests"
  task :compile => :environment do
    dist_dir = Rails.application.config.x.webpacker[:packs_dist_dir]
    result   = `WEBPACK_DIST_DIR=#{dist_dir} NODE_ENV=production ./bin/webpack --json`

    unless $?.success?
      puts JSON.parse(result)['errors']
      exit! $?.exitstatus
    end

    webpack_digests = JSON.parse(result)['assetsByChunkName'].each_with_object({}) do |(chunk, file), h|
      h[chunk] = file.is_a?(Array) ? file.find {|f| REGEX_MAP !~ f } : file
    end.to_json

    digests_path = Rails.application.config.x.webpacker[:digests_path]
    packs_path = Rails.root.join('public', dist_dir) || File.dirname(digests_path)
    packs_digests_path = digests_path || Rails.root.join(packs_path, 'digests.json')

    FileUtils.mkdir_p(packs_path)
    File.open(packs_digests_path, 'w+') { |file| file.write webpack_digests }

    puts "Compiled digests for all packs in #{packs_digests_path}: "
    puts webpack_digests
  end

  desc "Install webpacker in this application"
  task :install do
    if Rails::VERSION::MAJOR >= 5
      exec "./bin/rails app:template LOCATION=#{WEBPACKER_APP_TEMPLATE_PATH}"
    else 
      exec "./bin/rake rails:template LOCATION=#{WEBPACKER_APP_TEMPLATE_PATH}"
    end
  end

  namespace :install do
    desc "Install everything needed for react"
    task :react do
      config_path = Rails.root.join('config/webpack/shared.js')
      config = File.read(config_path)

      if config =~ /presets:\s*\[\s*\[\s*'latest'/
        puts "Replacing loader presets to include react in #{config_path}"
        config.gsub!(/presets:(\s*\[)(\s*)\[(\s)*'latest'/, "presets:\\1\\2'react',\\2[\\3'latest'")
      else
        puts "Couldn't automatically update loader presets in #{config_path}. Please set presets: [ 'react', [ 'latest', { 'es2015': { 'modules': false } } ] ]."
      end

      if config.include?("test: /\\.js(.erb)?$/")
        puts "Replacing loader test to include react in #{config_path}"
        config.gsub!("test: /\\.js(.erb)?$/", "test: /\\.jsx?(.erb)?$/")
      else
        puts "Couldn't automatically update loader test in #{config_path}. Please set test: /\.jsx?(.erb)?$/."
      end

      File.write config_path, config

      puts "Copying .babelrc to project directory"
      FileUtils.copy File.expand_path('../install/react/.babelrc', __dir__),
        Rails.root

      puts "Copying react example to app/javascript/packs/hello_react.jsx"
      FileUtils.copy File.expand_path('../install/react/hello_react.jsx', __dir__),
        Rails.root.join('app/javascript/packs/hello_react.jsx')

      exec './bin/yarn add --dev babel-preset-react && ./bin/yarn add react react-dom'
    end

    desc "Install everything needed for Angular"
    task :angular do
      config_path = Rails.root.join('config/webpack/shared.js')
      config = File.read(config_path)

      if config.include?('ts-loader')
        puts "The configuration file already has a reference to ts-loader, skipping the test rule..."
      else
        puts "Adding a loader rule to include ts-loader for .ts files in #{config_path}..."
        config.gsub!(/rules:(\s*\[)(\s*\{)/, "rules:\\1\\2 test: /\.ts$/, loader: 'ts-loader' },\\2")
      end

      if config =~ /["'].ts["']/
        puts "The configuration file already has a reference to .ts extension, skipping the addition of this extension to the list..."
      else
        puts "Adding '.ts' in loader extensions in #{config_path}..."
        config.gsub!(/extensions:(.*')(\s*\])/, "extensions:\\1, '.ts'\\2")
      end

      File.write config_path, config

      puts "Copying Angular example to app/javascript/packs/hello_angular.js"
      FileUtils.copy File.expand_path('../install/angular/hello_angular.js', __dir__),
        Rails.root.join('app/javascript/packs/hello_angular.js')

      puts "Copying Angular Hello app to app/javascript/hello_angular"
      FileUtils.copy_entry File.expand_path('../install/angular/hello_angular', __dir__),
        Rails.root.join('app/javascript/hello_angular')

      puts "Copying tsconfig.json to the Rails root directory"
      FileUtils.copy File.expand_path('../install/angular/tsconfig.json', __dir__),
        Rails.root.join('tsconfig.json')

      exec './bin/yarn add --dev typescript ts-loader && ./bin/yarn add "core-js zone.js rxjs @angular/core @angular/common @angular/compiler @angular/platform-browser @angular/platform-browser-dynamic"'
    end

    desc "Install everything needed for Vue"
    task :vue do
      config_path = Rails.root.join('config/webpack/shared.js')
      config = File.read(config_path)

      # Module resolution https://webpack.js.org/concepts/module-resolution/
      if config.include?("'vue$':'vue/dist/vue.common.js'")
        puts "Couldn't automatically update module resolution in #{config_path}. Please set resolve { alias:{ 'vue$':'vue/dist/vue.common.js' } }."
      else
        config.gsub!(/resolve:(\s*\{)(\s*)extensions/,"resolve:\\1\\2alias: { 'vue$':'vue/dist/vue.common.js' },\\2extensions")
      end

      if config.include?("loader: 'url-loader?mimetype=image/png'")
        puts "Couldn't automatically update url-loader in #{config_path}. Please set { test: /\.png$/, loader: 'url-loader?mimetype=image/png' }."
      else
        config.gsub!(/module:(\s*\{)(\s*)rules:(\s*)\[/,"module:\\1\\2rules:\\3[\\2  { test: /\.png$/, loader: 'url-loader?mimetype=image/png'},")
      end

      if config.include?("loader: 'vue-loader',")
        puts "Couldn't automatically update vue-loader in #{config_path}. Please set { test: /.vue$/, loader: 'vue-loader', options: { loaders: { 'scss': 'vue-style-loader!css-loader!sass-loader', 'sass': 'vue-style-loader!css-loader!sass-loader?indentedSyntax'}}}."
      else
        config.gsub!(/module:(\s*\{)(\s*)rules:(\s*)\[/,"module:\\1\\2rules:\\3[\\2  {\\2    test: /\.vue$/, loader: 'vue-loader',\\2    options: {\\2      loaders: { 'scss': 'vue-style-loader!css-loader!sass-loader', 'sass': 'vue-style-loader!css-loader!sass-loader?indentedSyntax'}\\2    }\\2  },")
      end

      File.write config_path, config

      puts "Copying the Vue example to app/javascript/packs/vue"
      FileUtils.copy File.expand_path('../install/vue/hello_vue.js', File.dirname(__FILE__)),
        Rails.root.join('app/javascript/packs/hello_vue.js')

      FileUtils.copy File.expand_path('../install/vue/app.vue', File.dirname(__FILE__)),
        Rails.root.join('app/javascript/packs/app.vue')

      exec "./bin/yarn add vue vue-loader vue-template-compiler sass-loader node-sass css-loader url-loader axios"
    end

  end
end

# Compile packs after we've compiled all other assets during precompilation
if Rake::Task.task_defined?('assets:precompile')
  Rake::Task['assets:precompile'].enhance do
    Rake::Task['webpacker:compile'].invoke
  end
end
