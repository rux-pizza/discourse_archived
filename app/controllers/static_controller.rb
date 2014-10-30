class StaticController < ApplicationController

  skip_before_filter :check_xhr, :redirect_to_login_if_required
  skip_before_filter :verify_authenticity_token, only: [:enter]

  def show
    return redirect_to('/') if current_user && params[:id] == 'login'

    map = {
      "faq" => {redirect: "faq_url", topic_id: "guidelines_topic_id"},
      "tos" => {redirect: "tos_url", topic_id: "tos_topic_id"},
      "privacy" => {redirect: "privacy_policy_url", topic_id: "privacy_topic_id"}
    }

    @page = params[:id]

    if map.has_key?(@page)
      site_setting_key = map[@page][:redirect]
      url = SiteSetting.send(site_setting_key)
      return redirect_to(url) unless url.blank?
    end

    # The /guidelines route ALWAYS shows our FAQ, ignoring the faq_url site setting.
    @page = 'faq' if @page == 'guidelines'

    # Don't allow paths like ".." or "/" or anything hacky like that
    @page.gsub!(/[^a-z0-9\_\-]/, '')

    if map.has_key?(@page)
      @topic = Topic.find_by_id(SiteSetting.send(map[@page][:topic_id]))
      raise Discourse::NotFound unless @topic
      @body = @topic.posts.first.cooked
      @faq_overriden = !SiteSetting.faq_url.blank?
      render :show, layout: !request.xhr?, formats: [:html]
      return
    end

    if I18n.exists?("static.#{@page}")
      render text: I18n.t("static.#{@page}"), layout: !request.xhr?, formats: [:html]
      return
    end

    file = "static/#{@page}.#{I18n.locale}"
    file = "static/#{@page}.en" if lookup_context.find_all("#{file}.html").empty?
    file = "static/#{@page}"    if lookup_context.find_all("#{file}.html").empty?

    if lookup_context.find_all("#{file}.html").any?
      render file, layout: !request.xhr?, formats: [:html]
      return
    end

    raise Discourse::NotFound
  end

  # This method just redirects to a given url.
  # It's used when an ajax login was successful but we want the browser to see
  # a post of a login form so that it offers to remember your password.
  def enter
    params.delete(:username)
    params.delete(:password)

    destination = "/"

    if params[:redirect].present? && !params[:redirect].match(login_path)
      begin
        forum_uri = URI(Discourse.base_url)
        uri = URI(params[:redirect])
        if uri.path.present? &&
           (uri.host.blank? || uri.host == forum_uri.host) &&
           uri.path !~ /\./
          destination = uri.path
        end
      rescue URI::InvalidURIError
        # Do nothing if the URI is invalid
      end
    end

    redirect_to destination
  end

  skip_before_filter :verify_authenticity_token, only: [:cdn_asset]

  def cdn_asset
    path = File.expand_path(Rails.root + "public/assets/" + params[:path])

    # SECURITY what if path has /../
    raise Discourse::NotFound unless path.start_with?(Rails.root.to_s + "/public/assets")

    expires_in 1.year, public: true

    response.headers["Expires"] = 1.year.from_now.httpdate
    response.headers["Access-Control-Allow-Origin"] = params[:origin]

    begin
      response.headers["Last-Modified"] = File.ctime(path).httpdate
      response.headers["Content-Length"] = File.size(path).to_s
    rescue Errno::ENOENT
      raise Discourse::NotFound
    end

    opts = { disposition: nil }
    opts[:type] = "application/javascript" if path =~ /\.js$/

    # we must disable acceleration otherwise NGINX strips
    # access control headers
    request.env['sendfile.type'] = ''
    send_file(path, opts)
  end

end
