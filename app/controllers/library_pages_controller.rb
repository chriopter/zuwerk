class LibraryPagesController < ApplicationController
  before_action :require_human!
  before_action :load_project
  before_action :load_page, only: %i[show update destroy reorder]
  before_action :load_tree

  def index
    page = @project.library_root || @project.library_pages.create!(title: "Home", creator: current_user)
    redirect_to project_library_page_path(@project, page)
  end

  def show
  end

  def create
    @new_page = @project.library_pages.new(library_page_params.except(:content).merge(creator: current_user))
    @new_page.parent = find_parent(library_page_params[:parent_id])
    @new_page.position = next_position(@new_page.parent)
    if @new_page.save
      redirect_to project_library_page_path(@project, @new_page), notice: "Page created."
    else
      @selected_page = @project.library_root
      render :show, status: :unprocessable_entity
    end
  end

  def update
    attributes = library_page_params
    attributes = attributes.except(:title) if @page == @project.library_root
    new_parent = @page.parent
    if attributes.key?(:parent_id)
      if @page == @project.library_root && attributes[:parent_id].present?
        @page.errors.add(:parent, "cannot move the first project page")
        return render :show, status: :unprocessable_entity
      end
      new_parent = find_parent(attributes[:parent_id])
    end
    LibraryPage.transaction do
      @page.move_to!(parent: new_parent, position: next_position(new_parent)) if new_parent != @page.parent
      @page.update!(attributes.except(:parent_id))
    end
    respond_to do |format|
      format.html { redirect_to project_library_page_path(@project, @page), notice: "Page saved." }
      format.json { head :no_content }
    end
  rescue ActiveRecord::RecordInvalid
    respond_to do |format|
      format.html { render :show, status: :unprocessable_entity }
      format.json { render json: { errors: @page.errors.full_messages }, status: :unprocessable_entity }
    end
  end

  def destroy
    if @page == @project.library_root
      redirect_to project_library_page_path(@project, @page), alert: "The first project page cannot be deleted."
    else
      parent = @page.parent || @project.library_pages.roots.where.not(id: @page.id).ordered.first
      @page.destroy!
      redirect_to(parent ? project_library_page_path(@project, parent) : project_library_pages_path(@project), notice: "Page deleted.")
    end
  end

  def reorder
    parent = find_parent(params[:parent_id])
    if @page == @project.library_root && parent
      @page.errors.add(:parent, "cannot move the first project page")
      raise ActiveRecord::RecordInvalid, @page
    end
    @page.move_to!(parent: parent, position: params.require(:position))
    head :no_content
  rescue ActiveRecord::RecordInvalid, ArgumentError, TypeError => error
    errors = error.respond_to?(:record) ? error.record.errors.full_messages : [ error.message ]
    render json: { errors: errors }, status: :unprocessable_entity
  end

  private
    def load_project
      @project = find_project(params[:project_id])
    end

    def load_page
      @page = @project.library_pages.find(params[:id])
      @selected_page = @page
    end

    def load_tree
      @pages = @project.library_pages.includes(:rich_text_content).ordered.to_a
      @root_pages = @pages.select { |page| page.parent_id.nil? }
      @children_by_parent = @pages.group_by(&:parent_id)
      @new_page ||= @project.library_pages.new(parent_id: params[:new_parent])
    end

    def library_page_params
      params.require(:library_page).permit(:title, :content, :parent_id)
    end

    def find_parent(parent_id)
      return if parent_id.blank?

      parent = @project.library_pages.find(parent_id)
      if @page&.persisted? && parent.id.in?(@page.subtree_ids)
        @page.errors.add(:parent, "cannot be inside itself")
        raise ActiveRecord::RecordInvalid, @page
      end
      parent
    end

    def next_position(parent)
      scope = parent ? parent.children : @project.library_pages.roots
      (scope.maximum(:position) || -1) + 1
    end
end
