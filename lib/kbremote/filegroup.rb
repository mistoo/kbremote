# coding: utf-8
require "date"

module KbRemote
  class FileGroup
    API_URI = "filegroup"
    attr_reader :id, :name, :awaiting_deployment, :files
    def initialize(api, data)
      @api = api
      @id = data[:fileGroupID]
      @name = data[:name]
      @awaiting_deployment = data[:awaitingDeployment]
      @files = data[:files]
      @files.sort_by!{ |f| f[:path] } if @files
    end

    def to_hash
      { fileGroupID: @id, name: @name, awaitingDeployment: @awaiting_deployment, files: @files }
    end

    def self.load(api, id)
      re = api.request(:get, "#{API_URI}/#{id}")
      files_re = api.request(:get, "filegroupfile/#{id}")
      if files_re[:files]
        re[:files] = files_re[:files].map do |fi|
          {
            name: fi[:fileName],
            path: fi[:filePath],
            display: fi[:display],
            isdir: fi[:isFolder],
            size: fi[:size],
            mtime: DateTime.parse(fi[:lastModified])
          }
        end
      end
      self.new(api, re)
    end

    def self.create(api, name)
      re = api.request(:post, "filegroup", body: { name: name })
      self.new(api, re[:filegroup])
    end

    def patch(name: nil, deploychanges: nil)
      props = [ :name, :deploychanges ]
      data = {}
      b = binding
      props.each do |prop|
        val = b.local_variable_get(prop)
        data[prop] = val unless val.nil?
      end
      raise ArgumentError, "need at least one of #{props.join(', ')}" if props.size.zero?
      re = @api.request(:patch, "#{API_URI}/#{@id}", body: data)
      re && re[:updated]
    end

    def awaiting_deployment?
      !awaiting_deployment
    end

    def deploy_changes
      patch(deploychanges: true)
    end

    def delete_file(path, remote_root: 'localcontent')
      remote_path = "#{remote_root}/#{path}"
      re = @api.request(:delete, "filegroupfile/#{@id}", body: { path: remote_path })
      re && re[:deleted] == true
    end

    def upload_file(path, remote_directory: nil, remote_root: 'localcontent')
      remote_path = File.basename(path)
      remote_path = "#{remote_directory}/#{remote_path}" if remote_directory
      remote_path = "#{remote_root}/#{remote_path}"

      KbRemote.debug{ "uploading file #{path} => #{remote_path}" }

      data = {
        filegroupid: @id,
        path: remote_path,
        file: File.new(path, "rb")
      }

      re = @api.request(:post, "filegroupfile", body: data, as_json: false)
      re && re[:uploaded] == true
    end

    def upload_dir(dirpath, remote_root: 'localcontent')
      remote_dir = File.basename(dirpath)
      ok = true
      Dir.foreach(dirpath) do |filename|
        next if filename == '.' || filename == '..'
        path = File.join(dirpath, filename)
        if File.file?(path)
          ok = upload_file(path, remote_directory: remote_dir, remote_root: remote_root)
        elsif File.directory?(path)
          ok = upload_dir(path, remote_root: File.join(remote_root, File.basename(remote_dir)))
        end
        raise RuntimeError, "#{path}: upload failed" unless ok
        #sleep 1                 # Too Many Requests (in demo mode?)
      end
      ok
    end
  end
end
