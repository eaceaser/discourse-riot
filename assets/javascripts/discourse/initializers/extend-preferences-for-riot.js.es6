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
        }
      }
    });
  }
}
