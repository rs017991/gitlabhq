import * as types from './mutation_types';
import { fetchDiffData } from '../../utils';

export const setDiffEndpoint = ({ commit }, path) => commit(types.SET_DIFF_ENDPOINT, path);

export const requestDiff = ({ commit }) => commit(types.REQUEST_DIFF);

export const receiveDiffSuccess = ({ commit }, response) =>
  commit(types.RECEIVE_DIFF_SUCCESS, response);

export const receiveDiffError = ({ commit }, response) =>
  commit(types.RECEIVE_DIFF_ERROR, response);

export const fetchDiff = ({ state, rootState, dispatch }) => {
  dispatch('requestDiff');

  return fetchDiffData(rootState, state.paths.diffEndpoint, 'sast')
    .then(data => {
      dispatch('receiveDiffSuccess', data);
    })
    .catch(() => {
      dispatch('receiveDiffError');
    });
};
