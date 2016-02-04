import PreferencesController from 'discourse/controllers/preferences';
import showModal from 'discourse/lib/show-modal';

export default {
  name: 'extend-preferences-for-riot',
  initialize() {
    PreferencesController.reopen({
      actions: {
        addRiotLink: function () {
          showModal('riot-account-link', {model: {}, title: 'riot.account_link_title'});
          this.controllerFor('modal').set('modalClass', 'riot-account-link-modal');
        },
        deleteRiotLink: function(acct) {
          const model = this.get("model");
          Discourse.ajax('/riot/link', {method: "DELETE", data: acct}).then((res) => {
            const links = model.riot_accounts;
            const filtered = links.filter((el) => {
              el.riot_id != acct.riot_id || el.riot_region != acct.riot_region
            });
            console.log(filtered);
            model.set("riot_accounts", filtered);
          }).catch((ex) => {
            bootbox.alert(I18n.t("riot.unlink_failed"));
          });
        }
      }
    });
  }
}
