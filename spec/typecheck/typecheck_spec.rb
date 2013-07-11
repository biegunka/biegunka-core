#!/usr/bin/env ruby
# -*- coding: utf-8 -*-

require "open3"
require "rspec"
require_relative "./spec_helper"


def compile file, opts
  external_command       = "ghc -fno-code #{opts.join(" ")} #{file}"
  stdout, stderr, status = Open3.capture3 external_command
  { stdout: stdout, stderr: stderr, exitcode: status.exitstatus }
end

def successes root
  Dir.glob "#{root}/should_compile/*"
end

def failures root
  Dir.glob "#{root}/should_fail/*"
end


options = []
here = File.expand_path File.dirname __FILE__
if File.exists? "cabal-dev"
  options << "-package-db=#{Dir.glob("cabal-dev/packages-*.conf").first}"
elsif File.exists? ".cabal-sandbox"
  options << "-package-db=#{Dir.glob(".cabal-sandbox/*-packages.conf.d").first}"
end

describe "typechecking," do
  context "when successful," do
    successes(here).each do |success|
      it "succeeds to compile #{success}" do
        process = compile(success, options)
        process[:exitcode].should == 0
        process[:stderr].should   == ""
      end
    end
  end

  context "when unsuccessful," do
    failures(here).each do |failure|
      it "fails to compile #{failure}" do
        process = compile(failure, options)
        process[:exitcode].should_not == 0

        contents = IO.read(failure)

        marked_stderr = Marked.parse contents, :STDERR, Marked::CommentStyle[:haskell]
        process[:stderr].should =~ /#{marked_stderr.split("\n").join(".+")}/m
      end
    end
  end
end