class Admin::RacesController < Admin::AdminController
  before_filter :assign_event, :only => [ :new, :create ]
  before_filter :assign_race, :only => [ :create, :destroy, :edit, :new, :update, :create_result ]
  before_filter :require_administrator_or_promoter, :only => [ :create, :destroy, :edit, :new, :update ]
  before_filter :require_administrator, :except => [ :create, :destroy, :edit, :new, :update ]
  layout "admin/application"
  
  def new
    render :edit
  end
  
  def create
    if @race.save
      flash[:notice] = "Created #{@race.name}"
      redirect_to edit_admin_race_path(@race)
    else
      render :edit
    end
  end

  def edit
    @disciplines = [''] + Discipline.find(:all).collect do |discipline|
      discipline.name
    end
    @disciplines.sort!
  end
  
  # Update existing Race
  # === Params
  # * id
  # * event: Attributes Hash
  # === Assigns
  # * event: Unsaved Race
  # === Flash
  # * warn
  def update
    if @race.update_attributes(params[:race])
      expire_cache
      flash[:notice] = "Updated #{@race.name}"
      return redirect_to(edit_admin_race_path(@race))
    end
    render :action => :edit
  end

  # Permanently destroy race and redirect to Event
  # === Params
  # * id
  # === Flash
  # * notice
  def destroy
    @race = Race.find(params[:id])
    @race.destroy
  end

  # Insert new Result
  # === Params
  # * before_result_id
  # === Flash
  # * notice
  def create_result
    @result = @race.create_result_before(params[:before_result_id])
    expire_cache
  end

  # Permanently destroy Result
  # === Params
  # * id
  # === Flash
  # * notice
  def destroy_result
    @result = Result.find(params[:result_id])
    @result.race.destroy_result @result
    @result.race.results true
  end
  
  
  private
  
  def assign_event
    if params[:event_id].present?
      @event = Event.find params[:event_id]
    elsif params[:race]
      @event = Event.find params[:race][:event_id]
    end
  end
  
  def assign_race
    if params[:id].present?
      @race = Race.find(params[:id])
    else
      @race = @event.races.build params[:race]
    end
  end
end
