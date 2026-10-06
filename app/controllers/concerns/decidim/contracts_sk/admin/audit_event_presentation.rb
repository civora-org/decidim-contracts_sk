# frozen_string_literal: true

module Decidim
  module ContractsSk
    module Admin
      # Audit-event presentation shared by the audit-trail viewer
      # (civora-org/civora-platform#92) and the admin dashboard's
      # recent-activity block (civora-org/civora-platform#126): ONE action
      # vocabulary and ONE set of label/actor/target/reason helpers, so the
      # two surfaces can never drift apart. Included into an admin
      # controller; the helpers are exposed to its views and rely on the
      # controller's route helpers and #t.
      module AuditEventPresentation
        extend ActiveSupport::Concern

        included do
          helper_method :audit_action_label, :audit_actor_name, :audit_target_info,
                        :audit_reason_for
        end

        # Deterministic newest-first ordering of the trail, id as the
        # tiebreaker (a total order, so a page never repeats or drops a row);
        # shared by the viewer and the dashboard's recent-activity block.
        INDEX_ORDER = { created_at: :desc, id: :desc }.freeze

        # The polymorphic target_type string the commands stamp on
        # contract-targeted audit events; the events for one contract are
        # filtered by (target_type, target_id) — plain column names on the
        # (table-prefixed) audit_events table.
        CONTRACT_TARGET_TYPE = "Decidim::ContractsSk::Contract"

        # The audit action vocabulary actually written by the commands,
        # mapped to their localized labels: the six lifecycle events reuse
        # the admin transition vocabulary verbatim (one vocabulary, never a
        # second one), while the CRZ-import, redaction-confirmation and
        # amendment-publish actions carry their own keys under
        # admin.audit_events.actions. Any unknown action falls back to a
        # humanized string — the label helper never raises (fail-closed,
        # the link_targets.rb precedent), so a future command action can
        # never 500 the viewer before its locale keys land.
        ACTION_KEYS = {
          "contract.submit" => "decidim.contracts_sk.admin.contracts.transition.submit",
          "contract.return" => "decidim.contracts_sk.admin.contracts.transition.return",
          "contract.approve" => "decidim.contracts_sk.admin.contracts.transition.approve",
          "contract.reject" => "decidim.contracts_sk.admin.contracts.transition.reject",
          "contract.return_self" => "decidim.contracts_sk.admin.audit_events.actions.return_self",
          "contract.approve_self" => "decidim.contracts_sk.admin.audit_events.actions.approve_self",
          "contract.reject_self" => "decidim.contracts_sk.admin.audit_events.actions.reject_self",
          "contract.publish" => "decidim.contracts_sk.admin.contracts.transition.publish",
          "contract.archive" => "decidim.contracts_sk.admin.contracts.transition.archive",
          "contract.redaction_confirmed" => "decidim.contracts_sk.admin.audit_events.actions.redaction_confirmed",
          "amendment.publish" => "decidim.contracts_sk.admin.audit_events.actions.amendment_publish",
          "contract.crz_filed" => "decidim.contracts_sk.admin.audit_events.actions.crz_filed",
          "contract.crz_filed_override" => "decidim.contracts_sk.admin.audit_events.actions.crz_filed_override",
          "contract.note_added" => "decidim.contracts_sk.admin.audit_events.actions.note_added",
          "contract.crz_mirror_absorbed" => "decidim.contracts_sk.admin.audit_events.actions.crz_mirror_absorbed",
          "crz_import_create" => "decidim.contracts_sk.admin.audit_events.actions.crz_import_create",
          "crz_import_update" => "decidim.contracts_sk.admin.audit_events.actions.crz_import_update"
        }.freeze

        private

        # The localized action label for an event: the frozen
        # command-vocabulary mapping above, or a humanized fallback for any
        # unknown action string — never a raise, never raw internals.
        def audit_action_label(action)
          key = ACTION_KEYS.fetch(action.to_s) { return action.to_s.humanize }

          t(key)
        end

        # The acting user's display name, nil-guarded: the actor column is
        # NOT NULL at write time, but the user row itself can be deleted
        # later, leaving the event's actor association empty on read. An
        # empty/missing name degrades to the localized unknown-actor label.
        def audit_actor_name(event)
          event.actor&.name.presence || t("decidim.contracts_sk.admin.audit_events.unknown_actor")
        end

        # Display info for the event's target: { label:, url: } when the
        # polymorphic row resolves, nil when it dangles (row gone) or its
        # class no longer loads (constantize raises inside the association
        # access). The rescue is the fail-closed boundary (the
        # resolve_link_target precedent): an unresolvable target can never
        # raise or leak internals — the view renders the localized
        # deleted-target label instead.
        #
        # Contract targets link to the record's edit page (the admin hub);
        # amendment targets label themselves by version and link to their
        # parent contract's amendment manager (nil url when the parent is
        # gone — the label then renders as plain text).
        def audit_target_info(event)
          target = event.target
          return nil if target.blank?

          case target
          when Contract
            contract_target_info(target)
          when Amendment
            amendment_target_info(target)
          end
        rescue StandardError
          nil
        end

        def contract_target_info(contract)
          { label: contract.title, url: edit_admin_contract_path(contract) }
        end

        def amendment_target_info(amendment)
          parent = amendment.contract
          {
            label: t("decidim.contracts_sk.admin.audit_events.amendment_target",
                     version: amendment.version),
            url: parent && admin_contract_amendments_path(parent)
          }
        end

        # The reviewer decision reason an event row may carry: only for a
        # live Contract target sitting in a decision state
        # (ContractLifecycle::DECISION_STATES) with a non-blank
        # review_reason — the same gate the edit page's decision banner
        # uses. Everything else the commands may have observed stays out of
        # the viewer (nothing payload-like beyond the identity title).
        def audit_reason_for(event)
          return nil unless event.target_type == CONTRACT_TARGET_TYPE

          contract = event.target
          # The override reason of a CRZ filing confirmation (civora-org/
          # civora-platform#125) is shown on its own audit row.
          return contract&.crz_filing_reason.presence if event.action == "contract.crz_filed_override"

          decision_reason(contract)
        rescue StandardError
          nil
        end

        def decision_reason(contract)
          return nil unless contract.present? && contract.review_reason.present?
          return nil unless ContractLifecycle::DECISION_STATES.include?(contract.state&.to_sym)

          contract.review_reason
        end
      end
    end
  end
end
