lock "3.2.1"

set :linked_dirs, %w{log public/assets public/system public/uploads tmp/pids tmp/cache tmp/sockets vendor/bundle }
set :linked_files, %w{config/database.yml config/newrelic.yml config/secrets.yml}

set :bundle_jobs, 4
set :bundle_without, %w{development test acceptance}.join(' ')

set :puma_threads, [ 8, 32 ]
set :puma_workers, 1

set :site_local_repo_url_branch, "deployment"

load "local/config/deploy.rb" if File.exist?("local/config/deploy.rb")

set :deploy_to, "/var/www/rails/#{fetch(:application)}"

set :repo_url, "git://github.com/scottwillson/racing_on_rails.git"
set :branch, "deployment"
set :site_local_repo_url, "git@github.com:scottwillson/#{fetch(:application)}-local.git"

set :user, "app"

namespace :deploy do
  desc "Deploy association-specific customizations"
  task :local_code do
    on roles :all do
      if fetch(:application) != "racing_on_rails"
        if fetch(:site_local_repo_url_branch)
          execute :git, "clone #{fetch(:site_local_repo_url)} -b #{fetch(:site_local_repo_url_branch)} #{release_path}/local"
        else
          execute :git, "clone #{fetch(:site_local_repo_url)} #{release_path}/local"
        end
        execute :chmod, "-R g+w #{release_path}/local"
        execute :ln, "-s #{release_path}/local/public #{release_path}/public/local"
      end
    end
  end

  task :registration_engine do
    on roles :all do
      if fetch(:application) == "obra" || fetch(:application) == "nabra"
        if test("[ -e \"#{release_path}/lib/registration_engine\" ]")
          execute :rm, "-rf \"#{release_path}/lib/registration_engine\""
        end

        if test("[ -L \"#{release_path}/lib/registration_engine\" ]")
          execute :rm, "-rf \"#{release_path}/lib/registration_engine\""
        end

        execute :git, "clone git@github.com:scottwillson/registration_engine.git -b deployment #{release_path}/lib/registration_engine"
      end
    end
  end

  task :copy_cache do
    on roles :app do
      %w{ bar bar.html events export people index.html results results.html teams teams.html }.each do |cached_path|
        run("if [ -e \"#{previous_release}/public/#{cached_path}\" ]; then cp -pr #{previous_release}/public/#{cached_path} #{release_path}/public/#{cached_path}; fi") rescue nil
      end
    end
  end
end

before "deploy:updated", "deploy:local_code"
before "deploy:updated", "deploy:registration_engine"
after "deploy:updated", "deploy:copy_cache"
