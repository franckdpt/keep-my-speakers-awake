import {test} from 'node:test';
import assert from 'node:assert/strict';
import {distributionConfig} from '../scripts/distribution.mjs';

test('Apple signing fails closed for missing or wrong distribution identities',()=>{
  assert.equal(distributionConfig({}).signed,false);
  assert.throws(()=>distributionConfig({KMSA_DISTRIBUTION:'developer-id'}));
  assert.throws(()=>distributionConfig({KMSA_DISTRIBUTION:'app-store',KMSA_SIGN_IDENTITY:'Developer ID Application: Example'}));
  assert.throws(()=>distributionConfig({KMSA_DISTRIBUTION:'development',KMSA_SIGN_IDENTITY:'Developer ID Application: Example'}));
  assert.throws(()=>distributionConfig({KMSA_DISTRIBUTION:'typo'}));
  assert.equal(distributionConfig({KMSA_DISTRIBUTION:'developer-id',KMSA_SIGN_IDENTITY:'Developer ID Application: Example'}).signed,true);
  assert.equal(distributionConfig({KMSA_DISTRIBUTION:'app-store'}).appStore,true);
});
