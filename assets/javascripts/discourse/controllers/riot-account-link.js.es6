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
      Discourse.ajax('/riot/link', {method: "POST", data: this.model}).then((res) => {
        this.set("model.riot_token", res.token);
        this.setProperties({"waitingForConfirmation": true});
      });
    },
    confirmLink() {
      const self = this;
      Discourse.ajax('/riot/link/confirm', {method: "POST", data: this.model}).then((res) => {
        if (res.confirmed) {
          this.setProperties({"confirmed": true});
          console.log("HI");
        } else {
          self.flash(I18n.t('riot.link.failed'));
        }
      });
    },
    cancelLink() {
      this.reset();
      this.send("closeModal");
    }
  }
});
