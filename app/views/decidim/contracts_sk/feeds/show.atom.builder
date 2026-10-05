# frozen_string_literal: true

# Atom feed (RFC 4287) of the newest published contracts. Every value goes
# through the builder's own escaping — never string interpolation into
# markup — so titles with markup characters or control characters still
# yield well-formed XML.
url_params = feed_url_params(@query)

atom_feed(language: I18n.locale.to_s,
          id: feed_id(@query),
          root_url: contracts_url(url_params),
          url: feed_url(feed_link_params(@query)),
          schema_date: Decidim::ContractsSk::FeedHelper::FEED_TAG_DATE) do |feed|
  feed.title feed_title
  feed.subtitle feed_subtitle(@query)
  feed.updated feed_updated_at(@contracts)
  feed.author { |author| author.name feed_organization_name }

  @contracts.each do |contract|
    time = feed_entry_time(contract)
    feed.entry(contract, id: feed_entry_id(contract), url: contract_url(contract, locale: nil),
                         published: time, updated: time) do |entry|
      entry.title contract.title
      entry.summary feed_entry_summary(contract), type: "text"
    end
  end
end
