"""Installer worker no-op, input update, cancellation and retained retry contracts."""
import copy
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import Mock, patch
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/"tools"))
from test_forever_inputs import Publishers, BUILD, RAW
import forever_inputs as current
import local_assembly as local


class Tests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory();self.addCleanup(self.temp.cleanup)
        self.root=Path(self.temp.name)
        game=self.root/"game";game.mkdir()
        exe=game/"Wow.exe";exe.write_bytes(b"fixture")
        (self.root/".build.info").write_bytes(RAW)
        self.resolution=current.discover(exe,Publishers().fetch,lambda _:BUILD)
        self.worker=local.Assembly.__new__(local.Assembly)
        self.worker.cache=self.root/"cache";self.worker.cache.mkdir()
        self.worker.job=self.worker.cache/"job";self.worker.job.mkdir()
        self.worker.resolution=self.resolution
        self.worker.tools={"compiler":"a"*64}
        self.worker.base_sha="b"*64
        self.worker.args=Mock(check_only=False,resume_runtime=None)
        self.worker.report=Mock()
        self.worker.verify_previous=Mock()
        self.previous=dict(format="rikui-local-assembly-v1",resolution=self.resolution,
                           tools=self.worker.tools,baseSHA256=self.worker.base_sha,listfileIdentity=local.listfile_identity(self.meta()))
        local.atomic(self.worker.cache/"latest.json",self.previous)

    def meta(self,tag="current-tag",updated="today"):
        return dict(tag_name=tag,assets=[dict(name="community-listfile.csv",id=1,size=20,updated_at=updated,digest=None)])

    def metadata(self):
        return patch.object(current,"download",return_value=current.canonical(self.meta()))

    def test_eight_terrain_workers_handoff_to_supported_road_process_limit(self):
        capture=self.root/"mesh.json";capture.write_bytes(b"verified mesh")
        travel=self.root/"travel.json";travel.write_bytes(b"verified travel")
        corpus=self.root/"corpus";(corpus/"audit").mkdir(parents=True)
        semantics=corpus/"audit/semantic-quests.json";semantics.write_bytes(b"verified semantics")
        self.worker.run=Mock()
        for capacity,expected in ((1,1),(2,2),(4,4),(8,4)):
            with self.subTest(capacity=capacity):
                self.worker.args.workers=capacity
                self.worker.build_roads(capture,self.root/"acquisition",self.root/"rasters",
                    self.root/"roads",corpus,travel,[0,1,2991])
                command,*arguments=self.worker.run.call_args.args
                self.assertEqual(command,"terrain/road_network.py")
                self.assertEqual(arguments[arguments.index("--workers")+1],expected)
                for flag,path in (("--expected-sha256",capture),("--semantic-sha256",semantics),
                        ("--travel-sha256",travel)):
                    self.assertEqual(arguments[arguments.index(flag)+1],local.digest(path))
                self.assertEqual([arguments[i+1] for i,value in enumerate(arguments) if value=="--world"],[0,1,2991])

    def test_worker_budget_respects_cpu_memory_and_eight_worker_cap(self):
        gib=1024**3
        for cpus,memory,expected in ((32,32*gib,8),(128,128*gib,8),(16,14*gib,4),(8,14*gib,2),
                (32,8*gib,2),(32,4*gib,1),(2,32*gib,1),(None,None,1),
                (32,None,1),(32,0,1)):
            with self.subTest(cpus=cpus,memory=memory):
                self.assertEqual(local.worker_budget(cpus,memory),expected)

    def test_cli_selects_capacity_automatically_and_preserves_explicit_override(self):
        base=["local_assembly.py","--runtime","runtime","--cache","cache","--status","status",
              "--result","result","--executable","Wow.exe","--base-bundle","base.zip"]
        for extra,memory,expected in (([],32*1024**3,8),(["--workers","1"],32*1024**3,1),([],None,1)):
            with self.subTest(extra=extra,memory=memory),patch.object(local.sys,"argv",base+extra),\
                    patch.object(local,"available_memory",return_value=memory),\
                    patch.object(local.os,"cpu_count",return_value=32),\
                    patch.object(local,"Assembly") as assembly,patch.object(local,"atomic"):
                assembly.return_value.prepare.return_value={"verified":True}
                local.main()
                self.assertEqual(assembly.call_args.args[0].workers,expected)
                assembly.return_value.lock.close.assert_called_once()

    @unittest.skipUnless(local.os.name=="nt","Windows physical-memory API")
    def test_actual_windows_memory_probe_supplies_positive_available_bytes(self):
        memory=local.available_memory()
        self.assertIsInstance(memory,int)
        self.assertGreater(memory,0)
        self.assertIn(local.worker_budget(local.os.cpu_count(),memory),range(1,9))

    def test_progress_atomic_write_retries_windows_reader_without_losing_receipt(self):
        path=self.root/"status.json"
        original=Path.replace
        attempts=[]
        def busy_reader(source,destination):
            attempts.append(1)
            if len(attempts)<3:raise PermissionError("Windows reader sharing")
            return original(source,destination)
        with patch.object(Path,"replace",busy_reader),patch.object(local.time,"sleep"):
            local.atomic(path,dict(state="prepared"))
        self.assertEqual(json.loads(path.read_bytes()),dict(state="prepared"))
        self.assertEqual(len(attempts),3)
        self.assertFalse(path.with_name(path.name+".next").exists())

    def test_verified_file_progress_is_bounded_and_pause_is_immediate(self):
        self.worker.cancel=self.worker.cache/"cancel"
        observer=self.worker.verification_progress("Checking prepared regions.")
        with patch.object(local.time,"monotonic",side_effect=[0,.2,.9,1.1,1.2]):
            for done in range(1,6):observer(done,5)
        self.assertEqual([call.kwargs["completed"] for call in self.worker.report.call_args_list],[1,4,5])
        self.assertTrue(all(call.kwargs["total"]==5 and call.kwargs["units"]=="files"
                            for call in self.worker.report.call_args_list))
        self.worker.report.reset_mock()
        self.worker.cancel.write_bytes(b"player paused")
        with self.assertRaises(InterruptedError):observer(1,10)
        self.worker.report.assert_not_called()

    def test_incomplete_generation_survives_orchestration_upgrade_only(self):
        old_tools={"tools/local_assembly.py":"a"*64,"tools/terrain/world_geometry.py":"b"*64}
        checkpoint=dict(format="rikui-preparation-checkpoint-v1",job=str(self.worker.cache/"job-prior"),
            resolution=self.resolution,tools=old_tools,baseSHA256=self.worker.base_sha,
            listfileIdentity=local.listfile_identity(self.meta()))
        old_tools["tools/terrain/world_bake_parallel.py"]="e"*64
        updated=dict(old_tools,**{"tools/local_assembly.py":"c"*64,"tools/terrain/world_bake_parallel.py":"f"*64})
        def select(document,tools=updated):
            return local.checkpoint_job(self.worker.cache,document,self.resolution,tools,
                self.worker.base_sha,local.listfile_identity(self.meta()))
        self.assertEqual(select(checkpoint),self.worker.cache/"job-prior")
        changed=dict(updated,**{"tools/terrain/world_geometry.py":"d"*64})
        self.assertIsNone(select(checkpoint,changed))
        outside=dict(checkpoint,job=str(self.root/"job-private"))
        self.assertIsNone(select(outside))
        moved=copy.deepcopy(checkpoint)
        moved["resolution"]["inputs"]["sources"]["provider"]["revision"]="f"*40
        moved["resolution"]["fingerprint"]=current.sha(current.canonical(moved["resolution"]["inputs"]))
        self.assertIsNone(select(moved))

    def test_verified_unchanged_update_is_actual_noop(self):
        self.worker.run=Mock(side_effect=AssertionError("No build should run"))
        with self.metadata():result=self.worker.prepare()
        self.assertEqual(result,self.previous)
        self.worker.verify_previous.assert_called_once()
        self.worker.run.assert_not_called()
        self.assertEqual(self.worker.report.call_args.kwargs["state"],"verified-no-op")

    def test_unchanged_bytes_follow_freshly_selected_installation(self):
        moved=copy.deepcopy(self.resolution)
        moved["installation"]["directory"]=str(self.root/"new-release-folder")
        moved["installation"]["executable"]=str(self.root/"new-release-folder/WowRelease.exe")
        self.worker.resolution=moved
        self.worker.run=Mock(side_effect=AssertionError("No rebuild for relocation"))
        with self.metadata():result=self.worker.prepare()
        self.assertEqual(result["resolution"]["installation"],moved["installation"])
        self.assertEqual(json.loads((self.worker.cache/"latest.json").read_bytes())["resolution"]["installation"],moved["installation"])
        self.worker.run.assert_not_called()

    def test_interface_update_reuses_verified_products_without_launching_geometry(self):
        import time
        corpus=self.root/"corpus";corpus.mkdir()
        (corpus/"manifest.json").write_bytes(b"verified corpus receipt")
        roads=self.root/"roads";roads.mkdir()
        receipt=roads/"road-network-receipt.json";receipt.write_bytes(b"verified road receipt")
        physical=self.root/"private-current-mesh";physical.write_bytes(b"preserve physical bytes")
        acquisition=self.root/"acquisition";(acquisition/"db2").mkdir(parents=True)
        (acquisition/"db2"/("Map-"+BUILD+".csv")).write_bytes(b"ID,MapName_lang\n0,Current Coast\n")
        self.previous.update(acquisition=str(acquisition),corpus=str(corpus),roads=str(roads),coverage=dict(worlds=[dict(worldMapID=0)],limits=["fixture unknowns"]))
        local.atomic(self.worker.cache/"latest.json",self.previous)
        self.worker.base_sha="c"*64
        self.worker.args.base_bundle=self.root/"new-interface.zip"
        self.worker.start=time.monotonic();self.worker.fresh=Mock()
        self.worker.run=Mock(side_effect=AssertionError("Geometry must not run for an interface update"))
        def assemble(base,corpus,roads,output):
            files={name:b"new interface fixture" for name in ("RikUI/RikUI.toc","RikUI/LICENSE","RikUI/generated/index.xml")}
            local.build_installer_bundle.write_payload("1.0.0-beta.15",output,files,["fixture"])
        before=receipt.stat().st_mtime_ns
        with self.metadata(),patch.object(local.build_installer_bundle,"assemble_local",side_effect=assemble):
            result=self.worker.prepare()
        self.worker.run.assert_not_called()
        self.assertEqual(physical.read_bytes(),b"preserve physical bytes")
        self.assertEqual(receipt.stat().st_mtime_ns,before)
        self.assertEqual(result["roads"],str(roads))
        self.assertEqual(result["coverage"]["regions"],[dict(mapID=0,name="Current Coast")])
        self.assertEqual(result["bundleInputs"]["base"],"c"*64)
        local.verify_local_bundle(result["bundle"],result["bundleInputs"])
        self.assertEqual(self.worker.verify_previous.call_count,2)
        self.worker.fresh.assert_called()

    def test_current_region_names_preserve_unknowns_and_reject_duplicate_identity(self):
        folder=self.root/"current-tables";(folder/"db2").mkdir(parents=True)
        table=folder/"db2"/("Map-"+BUILD+".csv")
        table.write_bytes(b"ID,MapName_lang\n0,Current Coast\n1,\n")
        worlds=[dict(worldMapID=0),dict(worldMapID=1),dict(worldMapID=991)]
        self.assertEqual(local.region_names(folder,worlds,BUILD),[
            dict(mapID=0,name="Current Coast"),dict(mapID=1,name="Map 1 (name unavailable)"),
            dict(mapID=991,name="Map 991 (name unavailable)")])
        table.write_bytes(b"ID,MapName_lang\n0,Current Coast\n0,Other Coast\n")
        with self.assertRaisesRegex(ValueError,"Duplicate current map"):
            local.region_names(folder,worlds,BUILD)

    def test_changed_provider_probe_requests_only_affected_products(self):
        self.worker.args.check_only=True
        revised=copy.deepcopy(self.resolution)
        revised["inputs"]["sources"]["provider"]["revision"]="f"*40
        revised["fingerprint"]=current.sha(current.canonical(revised["inputs"]))
        self.worker.resolution=revised
        with self.metadata():result=self.worker.prepare()
        self.assertEqual(result["rebuild"],["corpus","roads"])

    def test_changed_addon_and_listfile_are_detected(self):
        self.worker.args.check_only=True
        self.worker.base_sha="c"*64
        with patch.object(current,"download",return_value=current.canonical(self.meta("new-tag"))):
            result=self.worker.prepare()
        self.assertEqual(result["rebuild"],["roads","bundle"])

    def test_same_tag_replaced_publisher_asset_is_detected(self):
        self.worker.args.check_only=True
        with patch.object(current,"download",return_value=current.canonical(self.meta(updated="tomorrow"))):
            result=self.worker.prepare()
        self.assertEqual(result["rebuild"],["roads"])
        self.assertIn("listfile",result["changed"])

    def test_active_inventory_excludes_retained_interrupted_jobs(self):
        root=self.worker.job
        (root/"retained-old").mkdir()
        (root/"retained-old/private").write_bytes(b"preserved")
        (root/"accepted").write_bytes(b"active")
        (root/"preparation.log").write_bytes(b"log")
        self.assertEqual([row["path"] for row in local.inventory(root,active_only=True)],["accepted"])
        self.assertEqual((root/"retained-old/private").read_bytes(),b"preserved")

    def test_corrupt_outputs_are_never_noop(self):
        self.worker.args.check_only=True
        self.worker.verify_previous.side_effect=ValueError("changed output bytes")
        with self.metadata():result=self.worker.prepare()
        self.assertIn("unverified-bytes",result["changed"])
        self.assertEqual(result["rebuild"],["acquisition","corpus","bakes","roads"])

    def test_failed_step_preserves_bytes_and_allows_new_attempt(self):
        folder=self.worker.job/"acquisition";folder.mkdir()
        (folder/"partial").write_bytes(b"retained data")
        self.assertFalse(self.worker.reusable(folder,Mock(side_effect=ValueError("incomplete"))))
        self.assertFalse(folder.exists())
        retained=list(self.worker.job.glob("acquisition-retained-*"))
        self.assertEqual(len(retained),1)
        self.assertEqual((retained[0]/"partial").read_bytes(),b"retained data")
        folder.mkdir()
        verify=Mock()
        self.assertTrue(self.worker.reusable(folder,verify))
        self.assertEqual((retained[0]/"partial").read_bytes(),b"retained data")

    def test_interrupted_or_wrong_input_bundle_is_retained_before_retry(self):
        bundle=self.worker.job/"local-bundle.zip"
        bundle.write_bytes(b"interrupted ZIP")
        inputs=dict(base="b"*64,corpus="c"*64,roads="d"*64)
        local.atomic(bundle.with_suffix(".receipt.json"),dict(inputs=inputs,sha256=local.digest(bundle)))
        self.assertFalse(self.worker.reusable(bundle,lambda path:local.verify_local_bundle(path,inputs)))
        self.assertEqual(next(self.worker.job.glob("local-bundle.zip-retained-*")).read_bytes(),b"interrupted ZIP")
        files={name:b"fixture" for name in ("RikUI/RikUI.toc","RikUI/LICENSE","RikUI/generated/index.xml")}
        local.build_installer_bundle.write_payload("1.0.0-beta.15",bundle,files,["fixture"])
        local.atomic(bundle.with_suffix(".receipt.json"),dict(inputs=inputs,sha256=local.digest(bundle)))
        self.assertTrue(self.worker.reusable(bundle,lambda path:local.verify_local_bundle(path,inputs)))
        changed=dict(inputs,roads="e"*64)
        self.assertFalse(self.worker.reusable(bundle,lambda path:local.verify_local_bundle(path,changed)))

    def test_orphan_index_receipt_is_retained_without_touching_other_files(self):
        sidecar=self.worker.job/"placements.sqlite.receipt.json"
        sidecar.write_bytes(b"interrupted receipt")
        unrelated=self.worker.job/"player-data";unrelated.write_bytes(b"preserve")
        local.retain_owned_file(sidecar)
        self.assertFalse(sidecar.exists())
        self.assertEqual(next(self.worker.job.glob("placements*retained*")).read_bytes(),b"interrupted receipt")
        self.assertEqual(unrelated.read_bytes(),b"preserve")

    def test_retained_retry_accepts_canonical_spelling_of_owned_windows_paths(self):
        folder=self.worker.job/"acquisition";folder.mkdir()
        (folder/"partial").write_bytes(b"preserve")
        self.worker.cache=self.worker.cache/".."/"cache"
        self.worker.job=self.worker.cache/"job"
        self.assertFalse(self.worker.reusable(folder,Mock(side_effect=ValueError("incomplete"))))
        self.assertEqual(next(folder.parent.glob("acquisition-retained-*")).joinpath("partial").read_bytes(),b"preserve")
        outside=self.root/"private";outside.mkdir()
        with self.assertRaisesRegex(ValueError,"Retention outside"):
            self.worker.reusable(outside,Mock(side_effect=ValueError("invalid")))
        self.assertTrue(outside.exists())

    def test_fresh_preparation_admits_sixteen_gib_and_rejects_less_before_building(self):
        (self.worker.cache/"latest.json").unlink()
        self.worker.args.executable=self.resolution["installation"]["executable"]
        self.worker.args.base_bundle=self.root/"interface.zip"
        with self.metadata(),patch.object(local.shutil,"disk_usage",return_value=Mock(free=15*1024**3)):
            with self.assertRaisesRegex(ValueError,"Preparation needs 16 GiB"):
                self.worker.prepare()
        self.assertFalse((self.worker.cache/"preparing.json").exists())
        # At the exact admission boundary, preparation reaches source verification.
        # No mocked geometry producer or deletion can conceal an early disk rejection.
        with self.metadata(),patch.object(local.shutil,"disk_usage",return_value=Mock(free=16*1024**3)):
            self.worker.reusable=Mock(side_effect=InterruptedError("admitted; paused before acquisition"))
            with self.assertRaisesRegex(InterruptedError,"admitted; paused"):
                self.worker.prepare()
        self.assertTrue((self.worker.cache/"preparing.json").is_file())

    def test_retention_cannot_move_other_data(self):
        outside=self.root/"unrelated";outside.mkdir()
        with self.assertRaisesRegex(ValueError,"Retention outside"):
            self.worker.reusable(outside,Mock(side_effect=ValueError("invalid")))
        self.assertTrue(outside.exists())

    def test_pause_and_changed_input_stop_before_build_launch(self):
        self.worker.args.executable=self.resolution["installation"]["executable"]
        self.worker.cancel=self.worker.cache/"cancel"
        with patch.object(current,"discover",return_value=self.resolution):
            self.worker.cancel.write_bytes(b"pause")
            with self.assertRaises(InterruptedError):self.worker.fresh()
        self.worker.cancel.unlink()
        other=copy.deepcopy(self.resolution);other["fingerprint"]="f"*64
        with patch.object(current,"discover",return_value=other),self.assertRaisesRegex(ValueError,"changed"):
            self.worker.fresh()


if __name__=="__main__":unittest.main()
