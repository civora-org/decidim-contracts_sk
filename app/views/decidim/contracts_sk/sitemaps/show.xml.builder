# frozen_string_literal: true

# Sitemap protocol 0.9. lastmod is the record's updated_at in W3C datetime
# (UTC); the URL is the canonical detail page: locale: nil keeps the locale
# query param out that Decidim's default_url_options would otherwise add
# (always on 0.32, for a non-default locale on 0.31).
xml.instruct! :xml, version: "1.0", encoding: "UTF-8"
xml.urlset xmlns: "http://www.sitemaps.org/schemas/sitemap/0.9" do
  @contracts.each do |contract|
    xml.url do
      xml.loc contract_url(contract, locale: nil)
      xml.lastmod contract.updated_at.utc.iso8601
    end
  end
end
