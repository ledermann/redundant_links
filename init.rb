require File.dirname(__FILE__) + '/lib/redundant_links'
ActiveRecord::Base.send(:include, RedundantLinks)