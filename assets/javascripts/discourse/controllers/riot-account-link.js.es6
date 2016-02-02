import ModalFunctionality from 'discourse/mixins/modal-functionality';

export default Ember.Controller.extend(ModalFunctionality, {
  riotRegions: [
    {name: I18n.t('riot.regions.br'), value: "br"},
    {name: I18n.t('riot.regions.eune'), value: "eune"},
    {name: I18n.t('riot.regions.euw'), value: "euw"},
    {name: I18n.t('riot.regions.kr'), value: "kr"},
    {name: I18n.t('riot.regions.lan'), value: "lan"},
    {name: I18n.t('riot.regions.las'), value: "las"},
    {name: I18n.t('riot.regions.na'), value: "na"},
    {name: I18n.t('riot.regions.oce'), value: "oce"},
    {name: I18n.t('riot.regions.pbe'), value: "pbe"},
    {name: I18n.t('riot.regions.ru'), value: "ru"},
    {name: I18n.t('riot.regions.tr'), value: "tr"}
  ],
  waitingForConfirmation: false,

  reset() {
    this.setProperties({
      waitingForConfirmation: false
    });
  },

  actions: {
    linkAccount() {
      const self = this;
      Discourse.ajax('/riot/link', {method: "POST", data: this.model}).then((res) => {
        // TODO: I'm sure theres a better way to do this
        $("#modal-alert").hide();
        this.set("model.riot_token", res.token);
        this.setProperties({"waitingForConfirmation": true});
      }).catch((e) => {
        if (e.jqXHR && e.jqXHR.responseJSON) {
          const errorBody = e.jqXHR.responseJSON.errors.join(", ");
          self.flash(errorBody, 'error');
        } else {
          console.log(e);
          self.flash(I18n.t("riot.link.unknown_error"), 'error');
        }
      });
    },
    confirmLink() {
      const self = this;
      Discourse.ajax('/riot/link/confirm', {method: "POST", data: this.model}).then((res) => {
        if (res.confirmed) {
          // TODO: I'm sure theres a better way to do this
          $("#modal-alert").hide();
          this.setProperties({"confirmed": true});
        } else {
          self.flash(I18n.t('riot.link.failed'), 'error');
        }
      });
    },
    cancelLink() {
      this.reset();
      this.send("closeModal");
    }
  }
});
