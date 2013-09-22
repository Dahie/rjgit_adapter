# ~*~ encoding: utf-8 ~*~

require 'rjgit'

module Gollum
  module Git
    
    class Actor
      
      attr_accessor :name, :email
      attr_reader :actor
      
      def initialize(name, email)
        @name = name
        @email = email
        @actor = RJGit::Actor.new(name, email)
      end
      
      def output(time)
        @actor.output(time)
      end
      
    end
    
    class Blob
      def self.create(repo, options)
        #Grit::Blob.create(repo, :id => @sha, :name => name, :size => @size, :mode => @mode)
        blob = Grit::Blob.create(repo, options)
        self.new(blob)
      end
      
      def initialize(blob)
        @blob = blob
      end
      
      def data
        @blob.data
      end
      
      def name
        @blob.name
      end
      
      def mime_type
        @blob.mime_type
      end
      
      def is_symlink
        @blob.is_symlink
      end

      def symlink_target(base_path = nil)
        @blob.symlink_target(base_path)
      end
    end
    
    class Commit
      
      def initialize(commit)
        @commit = commit
      end
      
      def id
        @commit.id
      end
      alias_method :sha, :id
      
      def to_s
        @commit.id
      end
      
      def author
        author = @commit.actor
        Gollum::Git::Actor.new(author.name, author.email)
      end
      
      def message
        @commit.message
      end
      
      def tree
        Gollum::Git::Tree.new(@commit.tree)
      end
      
      # Grit::Commit.list_from_string(@wiki.repo, log)
      def self.list_from_string(repo, log)
        RJGit::Commit.list_from_string(repo, log)
      end
      
    end
    
    # Note that in Grit, the methods grep, rm, checkout, ls_files
    # are all passed to native via method_missing. Hence the uniform
    # method signatures.
    class Git
    
      def initialize(git)
        @git = git
      end
      
      def exist?
        @git.exist?
      end
      
      def grep(options={}, *args, &block)
        @git.grep(options, *args, &block)
      end
      
      # git.rm({'f' => true}, '--', path)
      def rm(options={}, *args, &block)
        @git.rm(options, *args, &block)
      end
      
      # git.checkout({}, 'HEAD', '--', path)
      def checkout(options={}, *args, &block)
        @git.checkout(options, *args, &block)
      end
      
      def rev_list(options, *refs)
        @git.rev_list(options, *refs)
      rescue Grit::GitRuby::Repository::NoSuchShaFound
        raise Gollum::Git::NoSuchShaFound
      end
      
      def ls_files(options={}, *args, &block)
        @git.ls_files(options, *args, &block)
      end
      
      def ls_tree(options={}, *args, &block)
        @git.native(:ls_tree, options, *args, &block)
        #         {:r => true, :l => true, :z => true}, sha)
      end
      
      def apply_patch(options={}, head_sha=nil, patch=nil)
        @git.apply_patch(options, head_sha, patch)
      end
      
      # @repo.git.cat_file({:p => true}, sha)
      def cat_file(options, sha)
        @git.cat_file(options, sha)
      end
      
      def diff(*args)
        @git.native(:diff, *args)
      end
      
      def log(options = {}, *args, &block)
        @git.native(:log, options, *args, &block)
      end
      
      def refs(options, prefix)
        @git.refs(options, prefix)
      end
      
    end
    
    class Index
      
      import 'org.eclipse.jgit.revwalk.RevWalk'
      
      def initialize(index)
        @index = index
        @current_tree = nil
      end
      
      def delete(path)
        @index.delete(path)
      end
      
      def add(path, data)
        @index.add(path, data)
      end
      
      # index.commit(@options[:message], parents, actor, nil, @wiki.ref)
      def commit(message, parents = nil, actor = nil, last_tree = nil, head = nil)
        actor = actor ? actor.actor : Gollum::Git::Actor.new("Gollum", "gollum@wiki")
        @index.commit(message, actor, parents, head)
      end
      
      def tree
        @index.treemap
      end
      
      def read_tree(id)
        walk = RevWalk.new(@index.jrepo)
          begin
            @index.current_tree = RJGit::Tree.new(@index.jrepo, nil, nil, walk.lookup_tree(ObjectId.from_string(id)))
          rescue
            raise Gollum::Git::NoSuchShaFound
          end
        @current_tree = Gollum::Git::Tree.new(@index.current_tree)
      end
      
      def current_tree
        @current_tree
      end
      
    end
    
    class Ref
      def initialize(name, commit)
        @name, @commit = name, commit
      end
      
      def name
        @name
      end
      
      def commit
        Gollum::Git::Commit.new(@commit)
      end
            
    end
    
    class Repo
      
      def initialize(path, options)
        @repo = RJGit::Repo.new(path, options)
      end
      
      def self.init(path, git_options = {}, repo_options = {})
        RJGit::Repo.init(path, git_options, repo_options)
        self.new(path, {:is_bare => false})
      end
      
      def self.init_bare(path, git_options = {}, repo_options = {})
        RJGit::Repo.init_bare(path, git_options, repo_options)
        self.new(path, {:is_bare => true})
      end
      
      def bare
        @repo.bare
      end
      
      def config
        @repo.config
      end
      
      def git
        @git ||= Gollum::Git::Git.new(@repo.git)
      end
      
      def commit(id)
        commit = @repo.commit(id)
        return nil if commit.nil?
        Gollum::Git::Commit.new(@repo.commit(id))
      end
      
      def commits(start = 'master', max_count = 10, skip = 0)
        @repo.commits(start, max_count).map{|commit| Gollum::Git::Commit.new(commit)}
      end
      
      # @wiki.repo.head.commit.sha
      def head
        Gollum::Git::Ref.new("refs/heads/master", @repo.head)
      end
      
      def index
        @index ||= Gollum::Git::Index.new(RJGit::Plumbing::Index.new(@repo))
      end
      
      def log(commit = 'master', path = nil, options = {})
        @repo.log(commit, path, options)
      end
      
      def path
        @repo.path
      end
      
      def update_ref(head, commit_sha)
        @repo.update_ref(head, commit_sha)
      end
     
    end
    
    class Tree
      
      def initialize(tree)
        @tree = tree
      end
      
      def id
        @tree.id
      end
      
      # if index.current_tree && tree = index.current_tree / (@wiki.page_file_dir || '/')
      def /(file)
        @tree.send(:/, file) 
      end
      
      def blobs
        return Array.new if @tree == {}
        @tree.blobs.map{|blob| Gollum::Git::Blob.new(blob) }
      end
    end
    
    class NoSuchShaFound < StandardError
    end
    
  end
end

# Monkey patching Grit's Blob class (taken from grit_ext.rb)
module Grit
  class Blob
    def is_symlink
      self.mode == 0120000
    end

    def symlink_target(base_path = nil)
      target = self.data
      new_path = File.expand_path(File.join('..', target), base_path)

      if File.file? new_path
        return new_path
      end
    end

    nil
  end
end