import { ajax } from 'discourse/lib/ajax';
import { popupAjaxError } from 'discourse/lib/ajax-error';
import showModal from "discourse/lib/show-modal";
import discourseComputed from "discourse-common/utils/decorators";
import { not } from "@ember/object/computed";

export default Ember.Component.extend ({
  classNames: 'featured-topics',
  notMobile: not('site.mobileView')
})