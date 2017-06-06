require "yaml"
require "shellwords"
require "fileutils"

class VMConnection
  VMS_ROOT = Rails.application.secrets.vms_root
  RAILROADY_PATH = Rails.application.secrets.railroady_path
  DOTOJSON_PATH = Rails.application.secrets.dotojson_path
  DOTOJSON_EXPORT_FILE = "models_dot".freeze
  DOTOJSON_EXPORT_PATH = DOTOJSON_PATH + "/" + DOTOJSON_EXPORT_FILE

  RAILROADY_TO_DOT_COMMAND =
    RAILROADY_PATH +
    " -M --transitive --show-belongs_to --all-columns > " +
    DOTOJSON_EXPORT_PATH +
    ";"

  SYSTEM_DEPENDENCIES =
    'export PATH="$PATH:$HOME/.rvm/bin"; source /home/miguel/.rvm/scripts/rvm'.freeze

  def initialize(report)
    @report = report
    @project = @report.project
  end

  def search_ruby_version
    read_gc_config_ruby || read_file_ruby || read_gemfile_ruby
  end

  def delete_gemset
    raise unless @report.ruby_version

    input = [SYSTEM_DEPENDENCIES]
    input << "rvm use #{@report.ruby_version}"
    input << "rvm --force gemset delete #{gemset}"
    Bundler.with_clean_env { bash(input.join(";")) }
  end

  def delete_repository
    FileUtils.rm_rf(File.join(VMS_ROOT, @project.github_owner, @project.github_name))
  end

  def read_simplecov_last_run(last_run_json_path)
    json = JSON.parse(File.read(last_run_json_path))
    if json["result"] && json["result"]["covered_percent"]
      json["result"]["covered_percent"]
    else
      false
    end
  end

  def disable_spring_in_rails_app
    puts "\n\n\n ----------------- Disable Spring in Rails app \n\n\n"
    execute_in_rails_app(["bin/spring binstub --remove --all"])
  end

  def get_simplecov_last_percent
    puts "\n\n\n ----------------- RUN TESTS \n\n\n"

    execute_in_rails_app(["RAILS_ENV=test bin/rake db:migrate"])
    # TODO: add desired test framework to .gc.yml
    # execute_in_rails_app(["RAILS_ENV=test bundle exec rake test"])
    execute_in_rails_app(["RAILS_ENV=test bundle exec rspec"])

    last_run_json_path = File.join(rails_fullpath, "coverage", ".last_run.json")
    return false unless File.exist?(last_run_json_path)

    read_simplecov_last_run(last_run_json_path)
  end

  def generate_files_and_read_json
    generate_dot && generate_json
    read_json_data || false
  end

  def generate_dot
    execute_in_rails_app([RAILROADY_TO_DOT_COMMAND])
    File.exist?(DOTOJSON_EXPORT_PATH) ? true : false
  end

  def generate_json
    Bundler.with_clean_env do
      system "
        cd #{DOTOJSON_PATH};
        ruby dotojson.rb #{DOTOJSON_EXPORT_FILE};
        rm #{DOTOJSON_EXPORT_FILE};
        mkdir -p #{tmp_fullpath};
        mv #{DOTOJSON_EXPORT_FILE}.json #{tmp_fullpath}/#{@report.project.github_owner}_#{@report.project.github_name}_#{@report.commit_hash}.json
      "
    end

    File.exist?(get_json_file_path(@report)) ? true : false
  end

  def get_gc_config(files)
    files.each do |file|
      return cat_in_rails_app(file) if exists_in_rails_app?(file)
    end
    nil
  end

  def repository_ready?
    repository_exists?
  end

  def prepare_repository
    unless repository_exists?
      return false unless clone_repository_and_fetch_commit
    end
    true
  end

  def prepare_gemset
    raise unless @report.ruby_version
    input = [SYSTEM_DEPENDENCIES]
    input << "cd #{rails_fullpath}"
    input << "rvm install #{@report.ruby_version}"
    input << "rvm use #{gemset} --create"
    input << "gem install bundle --no-document --no-ri"
    # TODO: adicionar SSH keys command
    input << "bundle install"

    Bundler.with_clean_env { bash(input.join(";")) }
  end

  def execute_in_rails_app(commands)
    input = [SYSTEM_DEPENDENCIES]
    input << "cd #{rails_fullpath}"
    input << "rvm use #{gemset}" if gemset
    input += commands

    Bundler.with_clean_env { bash(input.join(";")) }
  end

  def execute_in_repository(commands)
    input = [SYSTEM_DEPENDENCIES]
    input << "cd #{repository_fullpath}"
    input += commands

    Bundler.with_clean_env { bash(input.join(";")) }
  end

  def cat_in_rails_app(file)
    file_path = File.join(rails_fullpath, file)
    File.exist?(file_path) ? File.read(file_path) : false
  end

  def exists_in_rails_app?(path)
    File.exist?(File.join(rails_fullpath, path))
  end

  # Rails app might not be inside /repository
  def rails_fullpath
    File.join(repository_fullpath, @report.rails_app_path)
  end

  def delete_rake_tasks_folder
    FileUtils.rm_rf(File.join(rails_fullpath, "lib", "tasks"))
  end

  def read_json_data
    path = get_json_file_path(@report)
    File.exist?(path) ? File.read(path) : false
  end

  private

  def get_json_file_path(report)
    File.join(tmp_fullpath, report.project.github_owner + "_" + report.project.github_name + "_" + report.commit_hash + ".json")
  end

  def gemset
    "#{@report.ruby_version}@#{@report.project.github_owner}_#{@report.project.github_name}_#{@report.commit_hash}"
  end

  def home_fullpath
    return unless @project.github_owner && @project.github_name && @report.commit_hash
    File.join(
      VMS_ROOT,
      @project.github_owner,
      @project.github_name,
      @report.commit_hash
    )
  end

  def tmp_fullpath
    return unless @project.github_owner && @project.github_name
    File.join(home_fullpath, "tmp")
  end

  def repository_fullpath
    File.join(home_fullpath, "repository")
  end

  def clone_repository_and_fetch_commit
    FileUtils.mkdir_p(home_fullpath)
    system "
      cd #{home_fullpath};
      #{get_clone_command(@project)};
      mv #{@project.github_name} repository;
      #{get_fetch_command(@project)};
    "
  end

  def repository_exists?
    File.exist?(repository_fullpath) ? true : false
  end

  def bash(command)
    escaped_command = Shellwords.escape(command)
    system "/bin/bash --login -c #{escaped_command}"
  end

  def read_gemfile_ruby
    gemfile = File.open(File.join(rails_fullpath, "Gemfile")).read
    return unless gemfile

    gemfile.each_line do |line|
      if line =~ /^ruby\s["']\d+((\.\d+)+)?["']/
        return line.match(/\d+((\.\d+)+)?/)[0]
      end
    end
  end

  def read_file_ruby
    file_ruby = cat_in_rails_app(".ruby-version")
    file_ruby.match(/\d+((\.\d+)+)?/)[0] if file_ruby
  end

  def read_gc_config_ruby
    gc_config_yml = YAML.load(get_gc_config([".gc.yml"]))
    gc_config_yml["rvm"] ? gc_config_yml["rvm"].first : false
  end

  def get_fetch_command(project)
    if project.github_private
      "git fetch https://#{available_github_token(project)}:x-oauth-basic@github.com/#{project.github_owner}/#{project.github_name}.git #{@report.commit_hash}"
    else
      "git fetch origin #{@report.commit_hash}"
    end
  end

  def get_clone_command(project)
    if project.github_private
      "git clone https://#{available_github_token(project)}:x-oauth-basic@github.com/#{project.github_owner}/#{project.github_name}.git"
    else
      "git clone https://www.github.com/#{project.github_owner}/#{project.github_name}.git"
    end
  end

  def available_github_token(project)
    project.owner_user ? project.owner_user.github_token : project.added_by_user.github_token
  end
end
