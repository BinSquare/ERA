package main

import (
	"encoding/json"
	"errors"
	"os"
	"path/filepath"

	bolt "go.etcd.io/bbolt"
)

var (
	vmBucket      = []byte("vms")
	errPersist    = errors.New("vm persistence error")
	errNotFound   = errors.New("vm record not found")
	boltFilePerms = os.FileMode(0o600)
)

type BoltVMStore struct {
	db *bolt.DB
}

func NewBoltVMStore(stateRoot string) (*BoltVMStore, error) {
	dbPath := filepath.Join(stateRoot, stateDBFileName)
	if err := ensureDir(filepath.Dir(dbPath)); err != nil {
		return nil, err
	}
	db, err := bolt.Open(dbPath, boltFilePerms, nil)
	if err != nil {
		return nil, err
	}

	return &BoltVMStore{db: db}, nil
}

func (s *BoltVMStore) Close() error {
	if s == nil || s.db == nil {
		return nil
	}
	return s.db.Close()
}

func (s *BoltVMStore) Save(record VMRecord) error {
	if s == nil || s.db == nil {
		return errPersist
	}
	return s.db.Update(func(tx *bolt.Tx) error {
		bucket, err := tx.CreateBucketIfNotExists(vmBucket)
		if err != nil {
			return err
		}
		payload, err := json.Marshal(record)
		if err != nil {
			return err
		}
		return bucket.Put([]byte(record.ID), payload)
	})
}

func (s *BoltVMStore) Delete(vmID string) error {
	if s == nil || s.db == nil {
		return errPersist
	}
	return s.db.Update(func(tx *bolt.Tx) error {
		bucket, err := tx.CreateBucketIfNotExists(vmBucket)
		if err != nil {
			return err
		}
		return bucket.Delete([]byte(vmID))
	})
}

func (s *BoltVMStore) Get(vmID string) (VMRecord, error) {
	var record VMRecord
	if s == nil || s.db == nil {
		return record, errPersist
	}

	err := s.db.View(func(tx *bolt.Tx) error {
		bucket := tx.Bucket(vmBucket)
		if bucket == nil {
			return errNotFound
		}
		raw := bucket.Get([]byte(vmID))
		if raw == nil {
			return errNotFound
		}
		return json.Unmarshal(raw, &record)
	})
	return record, err
}

func (s *BoltVMStore) LoadAll() ([]VMRecord, error) {
	if s == nil || s.db == nil {
		return nil, errPersist
	}

	var records []VMRecord
	err := s.db.View(func(tx *bolt.Tx) error {
		bucket := tx.Bucket(vmBucket)
		if bucket == nil {
			return nil
		}
		return bucket.ForEach(func(_, v []byte) error {
			var record VMRecord
			if err := json.Unmarshal(v, &record); err != nil {
				return err
			}
			records = append(records, record)
			return nil
		})
	})
	return records, err
}
