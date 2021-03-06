#
# Author:: John Keiser (<jkeiser@opscode.com>)
# Copyright:: Copyright (c) 2012 Opscode, Inc.
# License:: Apache License, Version 2.0
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

require 'chef_fs/file_system/rest_list_dir'
require 'chef_fs/file_system/cookbook_dir'

module ChefFS
  module FileSystem
    class CookbooksDir < RestListDir
      def initialize(parent)
        super("cookbooks", parent)
      end

      def child(name)
        result = @children.select { |child| child.name == name }.first if @children
        result || CookbookDir.new(name, self)
      end

      def children
        @children ||= rest.get_rest(api_path).map { |key, value| CookbookDir.new(key, self, value) }.sort_by { |c| c.name }
      end

      def create_child_from(other)
        upload_cookbook_from(other)
      end

      def upload_cookbook_from(other)
        other_cookbook_version = other.chef_object
        # TODO this only works on the file system.  And it can't be broken into
        # pieces.
        begin
          uploader = Chef::CookbookUploader.new(other_cookbook_version, other.parent.file_path, :rest => rest)
          # Work around the fact that CookbookUploader doesn't understand chef_repo_path (yet)
          old_cookbook_path = Chef::Config.cookbook_path
          Chef::Config.cookbook_path = other.parent.file_path if !Chef::Config.cookbook_path
          begin
            # Chef 11 changes this API
            if uploader.respond_to?(:upload_cookbook)
              uploader.upload_cookbook
            else
              uploader.upload_cookbooks
            end
          ensure
            Chef::Config.cookbook_path = old_cookbook_path
          end
        rescue Net::HTTPServerException => e
          case e.response.code
          when "409"
            ui.error "Version #{other_cookbook_version.version} of cookbook #{other_cookbook_version.name} is frozen. Use --force to override."
            Chef::Log.debug(e)
            raise Exceptions::CookbookFrozen
          else
            raise
          end
        end
      end

      def can_have_child?(name, is_dir)
        is_dir
      end
    end
  end
end
