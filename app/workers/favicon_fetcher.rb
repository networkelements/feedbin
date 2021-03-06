require 'RMagick'
class FaviconFetcher
  include Sidekiq::Worker
  sidekiq_options retry: false

  def perform(host)
    favicon = Favicon.where(host: host).first_or_initialize
    if !updated_recently?(favicon.updated_at)
      update_favicon(favicon)
    end
  end

  def update_favicon(favicon)
    data = nil
    favicon_found = false

    favicon_url = find_favicon_link(favicon.host)
    if favicon_url
      data = download_favicon(favicon_url)
      favicon_found = true if data
    end

    if !favicon_found
      favicon_url = default_favicon_location(favicon.host)
      data = download_favicon(favicon_url)
    end

    if data
      favicon.favicon = data
    end

    favicon.save
  end

  def find_favicon_link(host)
    favicon_url = nil
    url = URI::HTTP.build(host: host)
    response = HTTParty.get(url, {timeout: 20})
    html = Nokogiri::HTML(response)
    favicon_links = html.search("//link[translate(@rel, 'ABCDEFGHIJKLMNOPQRSTUVWXYZ', 'abcdefghijklmnopqrstuvwxyz') = 'icon']/@href |" +
                                "//link[translate(@rel, 'ABCDEFGHIJKLMNOPQRSTUVWXYZ', 'abcdefghijklmnopqrstuvwxyz') = 'shortcut icon']/@href")

    if favicon_links.present?
      favicon_url = favicon_links.last.to_s
      favicon_url = URI.parse(favicon_url)
      if !favicon_url.host
        favicon_url.host = host
      end
      if !favicon_url.scheme
        favicon_url.scheme = 'http'
      end
    end
    favicon_url
  rescue
    nil
  end

  def default_favicon_location(host)
    URI::HTTP.build(host: host, path: "/favicon.ico")
  end

  def download_favicon(url)
    response = HTTParty.get(url, timeout: 20, verify: false)
    base64_favicon(response.body)
  end

  def base64_favicon(data)
    begin
      favicon = Magick::Image.from_blob(data)
    rescue Magick::ImageMagickError
      favicon = Magick::Image.from_blob(data) { |image| image.format = 'ico' }
    end
    favicon = favicon.last
    if favicon.columns > 32
      favicon = favicon.resize_to_fit(32, 32)
    end
    blob = favicon.to_blob { |image| image.format = 'png' }
    Base64.encode64(blob).gsub("\n", '')
  rescue
    nil
  end

  def updated_recently?(date)
    if date
      date > 1.day.ago
    else
      false
    end
  end

end
