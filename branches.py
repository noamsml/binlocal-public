#!/usr/bin/env python
import os
import sys
import subprocess
import traceback
import json
import functools
import unittest

def bash(cmd):
    run = subprocess.Popen(cmd, stdout=subprocess.PIPE, shell=True)
    if run.wait() != 0:
        print("OUTPUT: " + run.stdout.read().strip().decode('utf8'))
        raise Exception("command failed")
    return run.stdout.read().strip().decode('utf8')

@functools.cache
def reponame():
    bash("reponame")

def load_branch_configs():
    try: 
        with open(os.path.join(reponame(), "branch_configs.json")) as f:
            config = json.load(f)
            
            return {k:BranchConfig.from_json_config(v) for k,v in config.items()}
    except FileNotFoundError:
        print("No branch config found yet")

        return {}

class BranchConfig:
    def __init__(self, parent_branch=None, base_sha=None):
        self.parent_branch = parent_branch
        self.base_sha = base_sha
    @staticmethod
    def from_json_config(json_config):
        return BranchConfig(parent_branch=json_config['parent_branch'], base_sha=json_config['base_sha'])

class Branch:
    def __init__(self, branch_config=None):
        self.next_branches = []
        self.branch_config = branch_config

    def add_next_branch(self, branch):
        if branch in self.next_branches:
            raise Exception("Already seen branch " + branch)

        self.next_branches.append(branch)

class BranchDag:
    def __init__(self, branch_map=None, initial_branch_set=None):
        self.branch_map = branch_map
        self.initial_branch_set = initial_branch_set
    
def branches():
    bash("git for-each-ref --sort=-committerdate refs/heads/ --format=\"%(refname:short)\" | grep -v '^main$'").split()

def branch_dag(branch_list, branch_configs):
    branch_map = {}
    initial_branch_list = set([])

    def visit_branch(branch, next_branch):
        if branch in branch_map:
            if next_branch:
                branch_map[branch].add_next_branch(next_branch)
            return

        branch_config = branch_configs.get(branch, None)
        branch_map[branch] = Branch(branch_config)
        
        if next_branch: 
            branch_map[branch].add_next_branch(next_branch)
        
        if branch_config:
            visit_branch(branch_config.parent_branch, branch)
        else:
            initial_branch_list.add(branch)


    for branch in branch_list:
        if branch in branch_map:
            continue

        visit_branch(branch, None)
    
    return BranchDag(branch_map = branch_map, initial_branch_set = initial_branch_list)

class TestBranchDag(unittest.TestCase):
    def test_noconfigs(self):
        dag = branch_dag(["a", "b", "c"], {})
        self.assertEqual(set(["a", "b", "c"]), dag.initial_branch_set)
    def test_withdepth(self):
        dag = branch_dag(["b", "c", "a"], {"b": BranchConfig(parent_branch="a"), "c": BranchConfig(parent_branch="b")})
        self.assertEqual(set(["a"]), dag.initial_branch_set)
        self.assertEqual(["b"], dag.branch_map["a"].next_branches)
        self.assertEqual(["c"], dag.branch_map["b"].next_branches)

    
if __name__ == "__main__":
    unittest.main()