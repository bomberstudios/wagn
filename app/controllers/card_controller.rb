class CardController < ApplicationController

  helper :wagn, :card 
  layout :default_layout
  cache_sweeper :card_sweeper

  before_filter :create_ok, :only=>[ :new, :create ]

  before_filter :load_card!, :only=>[
    :changes, :comment, :denied, :edit, :options, :quick_update, 
    :related, :remove, :rollback, :save_draft, :update
  ]

  before_filter :load_card_with_cache, :only => [:line, :view, :open ]
  
  before_filter :edit_ok,   :only=>[ :edit, :update, :rollback, :save_draft] 
  before_filter :remove_ok, :only=>[ :remove ]
  
  #----------( Special cards )
  
  def index
    redirect_to(
      case
      when User.no_logins?;                 '/admin/setup'
      when home = System.setting('*home');  '/'+ home
      else { :controller=>'card',:action=>'show', :id=>Cardname.escape(System.site_title) }
      end
    )
  end

  def mine
    redirect_to :controller=>'card',:action=>'show', :id=>Cardname.escape(User.current_user.card.name)
  end

  #---------( VIEWING CARDS )
    
  def show
    # record this as a place to come back to.
    location_history.push(request.request_uri) if request.get?

    params[:_keyword] && params[:_keyword].gsub!('_',' ') ## this will be unnecessary soon.

    @card_name = Cardname.unescape(params['id'] || '')
    if (@card_name.nil? or @card_name.empty?) then    
      @card_name = System.site_title
    end             
    @card = CachedCard.get(@card_name)

    if @card.new_record? && ! @card.phantom?
      params[:card]={:name=>@card_name, :type=>params[:type]}
      if Cardtype.createable_cardtypes.empty? 
        return render :action=>'missing'
      else
        return self.new
      end
    end                                                                                  
    return unless view_ok # if view is not ok, it will render denied. return so we dont' render twice

    # rss causes infinite memory suck in rails 2.1.2.  
    unless Rails::VERSION::MAJOR >=2 && Rails::VERSION::MINOR >=2
      respond_to do |format|
        format.rss { raise("Sorry, RSS is broken in rails < 2.2") }
        format.html {}
      end
    end 
  end

  #----------------( MODIFYING CARDS )
  
  #----------------( creating)                                                               
  def new
    args = (params[:card] ||= {})
    args[:type] ||= params[:cardtype] # for /new/:cardtype shortcut in routes
    
    # don't pass a blank type as argument
    # look up other types in case Cardtype name is given instead of ruby type
    if args[:type]
      if args[:type].blank?
        args.delete(:type) 
      elsif ct=CachedCard.get_real(args[:type])    
        args[:type] = ct.name 
      end
    end

    # if given a name of a card that exists, got to edit instead
    if args[:name] and CachedCard.exists?(args[:name])
      render :text => "<span class=\"faint\">Oops, <strong>#{args[:name]}</strong> was recently created! try reloading the page to edit it</span>"
      return
    end

    @card = Card.new args                   
    if request.xhr?
      render :partial => 'views/new', :locals=>{ :card=>@card }
    else
      render :action=> 'new'
    end
  end
  
  def denial
    render :template=>'/card/denied', :status => 403
  end
  
  def create
    @card = Card.create params[:card]
    @card.multi_update(params[:cards]) if params[:multi_edit] and params[:cards] and @card.errors.empty?

    render_args = 
      case
        when !@card.errors.empty?;  {
          :status => 422,
          :inline=>"<%= error_messages_for :card %><%= javascript_tag 'scroll(0,0)' %>" 
        }
        when main_card?;  {:action=>'new_redirect', :status=>418 }          
          # according to rails / prototype docs:
          # :success: [...] the HTTP status code is in the 2XX range.
          # :failure: [...] the HTTP status code is not in the 2XX range.
          
          # however on 302 ie6 does not update the :failure area, rather it sets the :success area to blank..
          # for now, to get the redirect notice to go in the failure slot where we want it, 
          # we've chosen to render with the 'teapot' failure status: http://en.wikipedia.org/wiki/List_of_HTTP_status_codes
          
        else;              {:action=>'show'}
      end
    render render_args
  end
  
  #--------------( editing )
  
  def edit
    render :partial=>"card/edit/#{params[:attribute]}" if ['name','type'].member?(params[:attribute])
  end

  def update
    card_args=params[:card] || {}
    #fail "card params required" unless params[:card] or params[:cards]

    # ~~~ REFACTOR! -- this conflict management handling is sloppy
    @old_card = @card.clone
    @current_revision_id = @card.current_revision.id
    old_revision_id = card_args.delete(:current_revision_id) || @current_revision_id
    if old_revision_id.to_i != @current_revision_id.to_i
      changes  # FIXME -- this should probably be abstracted?
      @no_changes_header = true
      @changes = render_to_string :action=>'changes' 
      return render( :action=>:edit_conflict )
    end 
    # ~~~~~~  /REFACTOR ~~~~~ #
    
    case
    when params[:multi_edit]; @card.multi_update(params[:cards])
    when card_args[:type];       @card[:type]=card_args[:type]; @card.save
      #can't do this via update attributes: " Can't mass-assign these protected attributes: type"
      #might be addressable via attr_accessors?
    else;                     @card.update_attributes(card_args)     
    end  

    if @card.errors.on(:confirmation_required) && @card.errors.map {|e,f| e}.uniq.length==1  
      ## I don't get the second condition.  pls document  
      @confirm = @card.confirm_rename=true
      @card.update_link_ins = (@card.update_link_ins=='true')
      return render(:partial=>'card/edit/name', :status=>200)
    end
    
    return render_card_errors(@card) unless @card.errors.empty?
    @card = Card.find(card.id)
    render_update_slot render_to_string(:action=>'show')
  end

  def quick_update
    @card.update_attributes! params[:card]
    @card.errors.empty? ? render(:text=>'Success') : render_card_errors(@card)    
  end

  def save_draft
    @card.save_draft( params[:card][:content] )
    render(:update) do |page|
      page.wagn.messenger.log("saved draft of #{@card.name}")
    end
  end  

  def comment
    raise(Wagn::NotFound,"Action comment should be post with card[:comment]") unless request.post? and params[:card]
    @comment = params[:card][:comment];
    if User.current_user.login == 'anon'
      @author = params[:card][:comment_author]
      session[:comment_author] = @author
      @author = "#{@author} (Not signed in)"
    else
      @author = "[[#{User.current_user.card.name}]]"
    end
    @comment.gsub! /\n/, '<br/>'
    @card.comment = "<hr>#{@comment}<br/><p><em>&nbsp;&nbsp;--#{@author}.....#{Time.now}</em></p>"
    @card.save!   
    view = render_to_string(:action=>'show')
    render_update_slot view
  end

  def rollback
    load_card_and_revision
    @card.update_attributes! :content=>@revision.content
    render :action=>'show'
  end  

  #------------( deleting )

  def remove  
    if params[:card]
      @card.confirm_destroy = params[:card][:confirm_destroy]
    end
    if @card.destroy     
      discard_locations_for(@card)
      render_update_slot do |page,target|
        if @context=="main_1"
          page.wagn.messenger.note "#{@card.name} removed."
          page.redirect_to previous_location
          flash[:notice] =  "#{@card.name} removed"
        else 
          target.replace %{<div class="faint">#{@card.name} was just removed</div>}
          page.wagn.messenger.note( "#{@card.name} removed. ")  
        end
      end
    elsif @card.errors.on(:confirmation_required)
      render_update_slot render_to_string(:partial=>'confirm_remove')
    else
      render_card_errors(@card)
    end
  end



  #---------------( tabs )

  def view
    render :action=>'show'
  end   
  
  def open
    render :action=>'show'
  end

  def options
    @extension = card.extension
  end

  def changes
    load_card_and_revision
    @show_diff = (params[:mode] != 'false')
    @previous_revision = @card.previous_revision(@revision)
  end



  #------------------( views )

  def open
    render :action=>'show'
  end
    
  [:open_missing, :closed_missing].each do |method|
    define_method( method ) do
      load_card
      params[:view] = method
      if id = params[:replace]
        render_update_slot do |page, target|
          target.update render_to_string(:action=>'show')
        end
      else
        render :action=>'show'
      end
    end
  end

    
    
    
  #-------- ( MISFIT METHODS )  
  
  def auto_complete_for_navbox
    @stub = params['navbox']
    @items = Card.search( :complete=>@stub, :limit=>8, :sort=>'name' ) 
    render :inline => "<%= navbox_result @items, 'name', @stub %>"
  end
    
  def auto_complete_for_card_name
    complete = ''  
    # from pointers, the partial text is from fields called  pointer[N]
    # from the goto box, it is in card[name]
    params.keys.each do |key|
      complete = params[key] if key.to_s == 'name'
      next unless key.to_s =~ /card|pointer/ 
      complete = params[key].values[0]
    end

    if !params[:id].blank? && (card = Card["#{params[:id].tag_name}+*options"]) && card.type=='Search'
      @items = card.search( :complete=>complete, :limit=>8, :sort=>'name')
    else
      @items = Card.search( :complete=>complete, :limit=>8, :sort=>'name' )
    end
    render :inline => "<%= auto_complete_result @items, 'name' %>"
  end                                              
  
  
  # doesn't really seem to fit here.  may want to add new controller if methods accrue?        
  def add_field # for pointers only
    load_card! if params[:id]
    render :partial=>'types/pointer/field', :locals=>params.merge({:link=>"",:card=>@card})
  end
end

