namespace :fulltext do  
  desc "setup tsearch in postgres"
  task :prepare => :environment do
    cxn = ActiveRecord::Base.connection
    if System.enable_postgres_fulltext and is_postgresql?(cxn) 
      db = ActiveRecord::Base.configurations[RAILS_ENV]["database"]
      user = ActiveRecord::Base.configurations[RAILS_ENV]["username"]    


       # NOTE: this will only work if the user running the migration has sudo priveleges
		  tsearch_dir = System.postgres_tsearch_dir ? System.postgres_tsearch_dir : "#{System.postgres_src_dir}/contrib/tsearch2"
      `sudo -u postgres psql #{db} < #{tsearch_dir}/tsearch2.sql`
       cmd = %{ echo "alter table pg_ts_cfg owner to #{user}; } +
         %{ alter table pg_ts_cfgmap owner to #{user}; } + 
         %{ alter table pg_ts_dict owner to #{user}; } + 
         %{ alter table pg_ts_parser owner to #{user};" | sudo -u postgres psql #{db}
       }
       `#{cmd}`

       `echo "update pg_ts_cfg set locale = 'en_US' where ts_name = 'default'" | sudo -u postgres psql #{db}`   
       Rake::Task['fulltext:enable'].invoke

    else
      # FIXME: do whatever needs to happen for mysql? sqlite?
      #add_column :cards, :indexed_content, :text
    end                  
    
  end


  task :enable => :environment do
    cxn = ActiveRecord::Base.connection
    return unless  is_postgresql?(cxn)
    
    cxn.execute %{ alter table cards drop indexed_name, drop indexed_content; }
    cxn.execute %{ alter table cards add indexed_name tsvector, add indexed_content tsvector }
    
    cxn.execute %{ update cards set indexed_name = to_tsvector( name ) }
    cxn.execute %{ CREATE INDEX name_fti ON cards USING gist(indexed_name);  }    
    
    cxn.execute %{
      update cards set indexed_content = concat( setweight( to_tsvector( name ), 'A' ), 
      to_tsvector( (select content from revisions where id=cards.current_revision_id) ) ) 
    }
    cxn.execute %{ CREATE INDEX content_fti ON cards USING gist(indexed_content);  }    
    # choosing GIST for faster updates, at least for now.
    # see: http://www.postgresql.org/docs/8.3/static/textsearch-indexes.html
    cxn.execute %{ vacuum full analyze }
  end

  
  task :disable => :environment do
    cxn = ActiveRecord::Base.connection
    return unless  is_postgresql?(cxn)
    
    cxn.execute %{ alter table cards drop indexed_name, drop indexed_content; }
    cxn.execute %{ alter table cards add indexed_name varchar(8), add indexed_content varchar(8); }
  end
  
  task :wipe => :environment do
    desc 'get rid of extra tables for schema dumps (hard to get these back)'
    cxn = ActiveRecord::Base.connection
    return unless  is_postgresql?(cxn)
    %w{ cfg cfgmap dict parser }.each do |suffix|
      cxn.execute %{ drop table pg_ts_#{suffix}; }
    end
  end
    
end

def is_postgresql?(cxn)
  cxn.class.to_s.split('::').last == 'PostgreSQLAdapter'
end




        
# IF YOU GET
# could not access file "$libdir/tsearch2"
#
#  pg_config --pkglibdir
# and move the tsearch2.so into that path


# IF YOU GET:
#ERROR:  could not find tsearch config by locale
#
#
#  show lc_collate;
#  select * from pg_ts_cfg;
#  update pg_ts_cfg set locale = 'en_US.UTF-8' where ts_name = 'default';
